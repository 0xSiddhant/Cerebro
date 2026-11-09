import Foundation
import Network
import os

/// Stands in for `NWConnection` so its state changes and frames appear in the dashboard.
///
/// Network.framework has no Objective-C methods to hook, so this is the one way to see that traffic.
/// While Cerebro is off, every call only forwards to the real connection.
public final class MonitoredNWConnection: Sendable {
    /// A closure that's told about state changes.
    public typealias StateHandler = @Sendable (NWConnection.State) -> Void

    /// A closure that's given received content.
    public typealias ReceiveHandler = @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void

    /// The real connection, for anything this type doesn't forward.
    public let connection: NWConnection

    private let recorder: NWConnectionRecorder

    /// Creates a connection, as `NWConnection(host:port:using:)` does.
    public convenience init(host: NWEndpoint.Host, port: NWEndpoint.Port, using parameters: NWParameters) {
        self.init(wrapping: NWConnection(host: host, port: port, using: parameters))
    }

    /// Creates a connection, as `NWConnection(to:using:)` does.
    public convenience init(to endpoint: NWEndpoint, using parameters: NWParameters) {
        self.init(wrapping: NWConnection(to: endpoint, using: parameters))
    }

    /// Monitors an existing connection, keeping any state handler it already has.
    public init(wrapping connection: NWConnection) {
        self.connection = connection
        recorder = NWConnectionRecorder(endpoint: connection.endpoint, appStateHandler: connection.stateUpdateHandler)
        if SocketCaptureEngine.active != nil {
            connection.stateUpdateHandler = recorder.stateHandler()
        }
    }

    /// The connection's current state.
    public var state: NWConnection.State { connection.state }

    /// The connection's endpoint.
    public var endpoint: NWEndpoint { connection.endpoint }

    /// The connection's parameters.
    public var parameters: NWParameters { connection.parameters }

    /// The connection's current path.
    public var currentPath: NWPath? { connection.currentPath }

    /// Called when the state changes.
    public var stateUpdateHandler: StateHandler? {
        get { recorder.appStateHandler }
        set {
            recorder.appStateHandler = newValue
            connection.stateUpdateHandler = SocketCaptureEngine.active == nil ? newValue : recorder.stateHandler()
        }
    }

    /// Called when the connection's viability changes.
    public var viabilityUpdateHandler: (@Sendable (Bool) -> Void)? {
        get { connection.viabilityUpdateHandler }
        set { connection.viabilityUpdateHandler = newValue }
    }

    /// Called when a better path becomes available.
    public var betterPathUpdateHandler: (@Sendable (Bool) -> Void)? {
        get { connection.betterPathUpdateHandler }
        set { connection.betterPathUpdateHandler = newValue }
    }

    /// Called when the connection's path changes.
    public var pathUpdateHandler: (@Sendable (NWPath) -> Void)? {
        get { connection.pathUpdateHandler }
        set { connection.pathUpdateHandler = newValue }
    }

    /// Starts the connection.
    public func start(queue: DispatchQueue) {
        connection.start(queue: queue)
    }

    /// Restarts a connection that's waiting.
    public func restart() {
        connection.restart()
    }

    /// Closes the connection gracefully.
    public func cancel() {
        connection.cancel()
    }

    /// Closes the connection at once.
    public func forceCancel() {
        connection.forceCancel()
    }

    /// Cancels the current endpoint and tries the next.
    public func cancelCurrentEndpoint() {
        connection.cancelCurrentEndpoint()
    }

    /// Groups sends and receives, as `NWConnection.batch` does.
    public func batch(_ block: () -> Void) {
        connection.batch(block)
    }

    /// Sends content, as `NWConnection.send` does.
    public func send(
        content: Data?,
        contentContext: NWConnection.ContentContext = .defaultMessage,
        isComplete: Bool = true,
        completion: NWConnection.SendCompletion
    ) {
        guard SocketCaptureEngine.active != nil else {
            connection.send(
                content: content, contentContext: contentContext, isComplete: isComplete, completion: completion)
            return
        }
        connection.send(
            content: content,
            contentContext: contentContext,
            isComplete: isComplete,
            completion: recorder.recording(completion, sending: content, in: contentContext)
        )
    }

    /// Receives bytes, as `NWConnection.receive` does.
    public func receive(
        minimumIncompleteLength: Int,
        maximumLength: Int,
        completion: @escaping ReceiveHandler
    ) {
        connection.receive(
            minimumIncompleteLength: minimumIncompleteLength,
            maximumLength: maximumLength,
            completion: recorder.recording(completion)
        )
    }

    /// Receives a whole message, as `NWConnection.receiveMessage` does.
    public func receiveMessage(completion: @escaping ReceiveHandler) {
        connection.receiveMessage(completion: recorder.recording(completion))
    }
}

/// What the wrapper's callbacks need. It holds neither the wrapper nor the connection, so they can
/// keep it alive: `NWConnection` still delivers `.cancelled` after the app lets go of its wrapper.
private final class NWConnectionRecorder: Sendable {
    typealias ReceiveHandler = MonitoredNWConnection.ReceiveHandler

    private let id = UUID()
    private let endpoint: NWEndpoint
    private let identity = SocketIdentitySlot()
    private let storedAppStateHandler: OSAllocatedUnfairLock<MonitoredNWConnection.StateHandler?>
    private let isFinished = OSAllocatedUnfairLock(initialState: false)

    init(endpoint: NWEndpoint, appStateHandler: MonitoredNWConnection.StateHandler?) {
        self.endpoint = endpoint
        storedAppStateHandler = OSAllocatedUnfairLock(initialState: appStateHandler)
    }

    var appStateHandler: MonitoredNWConnection.StateHandler? {
        get { storedAppStateHandler.withLock { $0 } }
        set { storedAppStateHandler.withLock { $0 = newValue } }
    }

    func stateHandler() -> MonitoredNWConnection.StateHandler {
        { [self] state in
            record(state)
            appStateHandler?(state)
        }
    }

    func recording(
        _ completion: NWConnection.SendCompletion,
        sending content: Data?,
        in context: NWConnection.ContentContext
    ) -> NWConnection.SendCompletion {
        let payload = content.flatMap { $0.isEmpty ? nil : Self.payload($0, in: context) }
        guard case .contentProcessed(let handler) = completion else {
            recordSent(payload, didFail: false)
            return completion
        }
        return .contentProcessed { [self] error in
            recordSent(payload, didFail: error != nil)
            if let error {
                recordFailure(error)
            }
            handler(error)
        }
    }

    func recording(_ completion: @escaping ReceiveHandler) -> ReceiveHandler {
        guard SocketCaptureEngine.active != nil else { return completion }
        return { [self] data, context, isComplete, error in
            if let data, !data.isEmpty, let engine = SocketCaptureEngine.active {
                engine.submit(Self.payload(data, in: context), .received, on: identity(with: engine))
            }
            if let error {
                recordFailure(error)
            }
            completion(data, context, isComplete, error)
        }
    }

    private func identity(with engine: SocketCaptureEngine) -> SocketIdentity {
        identity.value {
            var url: URL?
            if case .url(let endpointURL) = endpoint {
                url = endpointURL
            }
            return engine.identity(id: id, source: .nwConnection, url: url, fallbackName: endpoint.debugDescription)
        }
    }

    private func record(_ state: NWConnection.State) {
        guard let engine = SocketCaptureEngine.active else { return }
        let event = Self.event(for: state)
        if Self.isFinal(event), !markFinished() {
            return
        }
        engine.submit(event, on: identity(with: engine))
    }

    private func recordSent(_ payload: SocketPayload?, didFail: Bool) {
        guard let payload, let engine = SocketCaptureEngine.active else { return }
        engine.submit(payload, .sent, didFail: didFail, on: identity(with: engine))
    }

    private func recordFailure(_ error: NWError) {
        guard let engine = SocketCaptureEngine.active, markFinished() else { return }
        engine.submit(.failed(error.debugDescription), on: identity(with: engine))
    }

    /// Returns whether this is the first end, because one failure surfaces in several callbacks.
    private func markFinished() -> Bool {
        isFinished.withLock { isFinished in
            defer { isFinished = true }
            return !isFinished
        }
    }

    private static func isFinal(_ event: SocketEvent) -> Bool {
        switch event {
        case .closed, .failed: return true
        default: return false
        }
    }

    private static func event(for state: NWConnection.State) -> SocketEvent {
        switch state {
        case .ready: return .opened
        case .cancelled: return .closed(code: nil, reason: nil)
        case .failed(let error): return .failed(error.debugDescription)
        case .waiting(let error): return .stateChanged("Waiting: \(error.debugDescription)")
        case .preparing: return .stateChanged("Preparing")
        case .setup: return .stateChanged("Setup")
        @unknown default: return .stateChanged("Unknown state")
        }
    }

    /// A frame is text only if WebSocket framing says so. Everything else on a raw connection is bytes.
    private static func payload(_ data: Data, in context: NWConnection.ContentContext?) -> SocketPayload {
        let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
        guard (metadata as? NWProtocolWebSocket.Metadata)?.opcode == .text,
            let text = String(data: data, encoding: .utf8)
        else { return .binary(data) }
        return .text(text)
    }
}
