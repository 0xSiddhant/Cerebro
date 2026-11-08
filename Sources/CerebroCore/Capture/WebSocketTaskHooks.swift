import Foundation
import ObjectiveC
import os

/// Captures `URLSessionWebSocketTask` with no change to the app, by hooking its public methods.
///
/// A hook hands activity to the pipeline and returns, so `send` and `receive` run at normal speed. The
/// `async` forms call these same Objective-C methods, so they're covered too. Each hook replaces the
/// method's implementation rather than exchanging selectors, and calls the original with its real selector.
enum WebSocketTaskHooks {
    private typealias SendCompletion = @convention(block) (NSError?) -> Void
    private typealias ReceiveCompletion = @convention(block) (NSObject?, NSError?) -> Void
    private typealias SendHook =
        @convention(block) (URLSessionWebSocketTask, NSObject, @escaping SendCompletion) -> Void
    private typealias ReceiveHook = @convention(block) (URLSessionWebSocketTask, @escaping ReceiveCompletion) -> Void
    private typealias PingHook = @convention(block) (URLSessionWebSocketTask, @escaping SendCompletion) -> Void

    /// Safety for `@unchecked Sendable`: both are opaque runtime pointers that never change.
    private struct InstalledHook: @unchecked Sendable {
        let method: Method
        let original: IMP
    }

    private static let installed = OSAllocatedUnfairLock<[InstalledHook]>(initialState: [])

    static func install() {
        guard let taskClass = concreteTaskClass() else { return }
        hookResume(on: taskClass)
        hookSend(on: taskClass)
        hookReceive(on: taskClass)
        hookPing(on: taskClass)
        hookCancelWithCode(on: taskClass)
        hookCancel(on: taskClass)
    }

    static func uninstall() {
        let hooks = installed.withLock { hooks -> [InstalledHook] in
            defer { hooks.removeAll() }
            return hooks
        }
        for hook in hooks {
            method_setImplementation(hook.method, hook.original)
        }
    }

    /// The system's own subclass does the work, and only an instance can name it with public API.
    private static func concreteTaskClass() -> AnyClass? {
        guard let url = URL(string: "ws://localhost") else { return nil }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        return type(of: session.webSocketTask(with: url))
    }

    /// Replaces a method, doing nothing if this OS doesn't have it, so capture can never crash the app.
    private static func replace(_ name: String, on taskClass: AnyClass, with makeHook: (IMP, Selector) -> Any) {
        let selector = NSSelectorFromString(name)
        guard let inherited = class_getInstanceMethod(taskClass, selector) else { return }
        let original = method_getImplementation(inherited)
        class_replaceMethod(
            taskClass,
            selector,
            imp_implementationWithBlock(makeHook(original, selector)),
            method_getTypeEncoding(inherited)
        )
        guard let method = class_getInstanceMethod(taskClass, selector) else { return }
        let hook = InstalledHook(method: method, original: original)
        installed.withLock { $0.append(hook) }
    }

    private static func hookResume(on taskClass: AnyClass) {
        typealias Original = @convention(c) (URLSessionWebSocketTask, Selector) -> Void
        replace("resume", on: taskClass) { implementation, selector in
            let original = unsafeBitCast(implementation, to: Original.self)
            let hook: @convention(block) (URLSessionWebSocketTask) -> Void = { task in
                if let (engine, record) = current(for: task), record.markStarted() {
                    engine.submit(.stateChanged("Connecting"), on: record.identity)
                }
                original(task, selector)
            }
            return hook
        }
    }

    private static func hookSend(on taskClass: AnyClass) {
        typealias Original =
            @convention(c) (URLSessionWebSocketTask, Selector, NSObject, @escaping SendCompletion) -> Void
        replace("sendMessage:completionHandler:", on: taskClass) { implementation, selector in
            let original = unsafeBitCast(implementation, to: Original.self)
            let hook: SendHook = { task, message, completion in
                original(task, selector, message) { error in
                    if let (engine, record) = current(for: task) {
                        recordSend(of: message, error: error, on: task, record, engine)
                    }
                    completion(error)
                }
            }
            return hook
        }
    }

    private static func hookReceive(on taskClass: AnyClass) {
        typealias Original = @convention(c) (URLSessionWebSocketTask, Selector, @escaping ReceiveCompletion) -> Void
        replace("receiveMessageWithCompletionHandler:", on: taskClass) { implementation, selector in
            let original = unsafeBitCast(implementation, to: Original.self)
            let hook: ReceiveHook = { task, completion in
                original(task, selector) { message, error in
                    if let (engine, record) = current(for: task) {
                        if let error {
                            recordFailure(error, on: task, record, engine)
                        } else if let payload = message.flatMap(payload) {
                            noteOpened(record, engine)
                            engine.submit(payload, .received, on: record.identity)
                        }
                    }
                    completion(message, error)
                }
            }
            return hook
        }
    }

    private static func hookPing(on taskClass: AnyClass) {
        typealias Original = @convention(c) (URLSessionWebSocketTask, Selector, @escaping SendCompletion) -> Void
        replace("sendPingWithPongReceiveHandler:", on: taskClass) { implementation, selector in
            let original = unsafeBitCast(implementation, to: Original.self)
            let hook: PingHook = { task, completion in
                if let (engine, record) = current(for: task) {
                    engine.submit(.ping, on: record.identity)
                }
                original(task, selector) { error in
                    if let (engine, record) = current(for: task) {
                        if let error {
                            recordFailure(error, on: task, record, engine)
                        } else {
                            noteOpened(record, engine)
                            engine.submit(.pong, on: record.identity)
                        }
                    }
                    completion(error)
                }
            }
            return hook
        }
    }

    private static func hookCancelWithCode(on taskClass: AnyClass) {
        typealias Original = @convention(c) (URLSessionWebSocketTask, Selector, Int, NSData?) -> Void
        replace("cancelWithCloseCode:reason:", on: taskClass) { implementation, selector in
            let original = unsafeBitCast(implementation, to: Original.self)
            let hook: @convention(block) (URLSessionWebSocketTask, Int, NSData?) -> Void = { task, code, reason in
                if let (engine, record) = existing(for: task), record.markClosed() {
                    engine.submit(.closed(code: code, reason: text(of: reason as Data?)), on: record.identity)
                }
                original(task, selector, code, reason)
            }
            return hook
        }
    }

    private static func hookCancel(on taskClass: AnyClass) {
        typealias Original = @convention(c) (URLSessionWebSocketTask, Selector) -> Void
        replace("cancel", on: taskClass) { implementation, selector in
            let original = unsafeBitCast(implementation, to: Original.self)
            let hook: @convention(block) (URLSessionWebSocketTask) -> Void = { task in
                if let (engine, record) = existing(for: task), record.markClosed() {
                    engine.submit(closeEvent(of: task), on: record.identity)
                }
                original(task, selector)
            }
            return hook
        }
    }

    /// A failure on a socket that's already closed is only the fallout of that close, so it's dropped.
    private static func recordFailure(
        _ error: NSError,
        on task: URLSessionWebSocketTask,
        _ record: WebSocketTaskRecord,
        _ engine: SocketCaptureEngine
    ) {
        guard record.markClosed() else { return }
        let event = task.closeCode == .invalid ? SocketEvent.failed(error.localizedDescription) : closeEvent(of: task)
        engine.submit(event, on: record.identity)
    }

    /// A send that failed still shows, because that's the message a developer most wants to see.
    private static func recordSend(
        of message: NSObject,
        error: NSError?,
        on task: URLSessionWebSocketTask,
        _ record: WebSocketTaskRecord,
        _ engine: SocketCaptureEngine
    ) {
        if error == nil {
            noteOpened(record, engine)
        }
        if let payload = payload(of: message) {
            engine.submit(payload, .sent, didFail: error != nil, on: record.identity)
        }
        if let error {
            recordFailure(error, on: task, record, engine)
        }
    }

    /// Only the app's delegate sees the handshake, so the first thing to succeed is the proof it worked.
    private static func noteOpened(_ record: WebSocketTaskRecord, _ engine: SocketCaptureEngine) {
        if record.markOpened() {
            engine.submit(.opened, on: record.identity)
        }
    }

    /// URLSession also calls `cancel` on itself when a server's close arrives with no receive waiting,
    /// so the code and reason are read from the task rather than assumed to be missing.
    private static func closeEvent(of task: URLSessionWebSocketTask) -> SocketEvent {
        guard task.closeCode != .invalid else { return .closed(code: nil, reason: nil) }
        return .closed(code: task.closeCode.rawValue, reason: text(of: task.closeReason))
    }

    private static func current(for task: URLSessionWebSocketTask) -> (SocketCaptureEngine, WebSocketTaskRecord)? {
        guard let engine = SocketCaptureEngine.active else { return nil }
        return (engine, WebSocketTaskRecord.of(task, engine: engine))
    }

    /// A cancel on a task that never ran isn't a socket, and start's own probe task is exactly that.
    private static func existing(for task: URLSessionWebSocketTask) -> (SocketCaptureEngine, WebSocketTaskRecord)? {
        guard let engine = SocketCaptureEngine.active, let record = WebSocketTaskRecord.existing(on: task) else {
            return nil
        }
        return (engine, record)
    }

    /// These are the public properties of `NSURLSessionWebSocketMessage`, which Swift doesn't import.
    private static func payload(of message: NSObject) -> SocketPayload? {
        if let text = message.value(forKey: "string") as? String {
            return .text(text)
        }
        return (message.value(forKey: "data") as? Data).map(SocketPayload.binary)
    }

    private static func text(of reason: Data?) -> String? {
        reason.flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// What Cerebro remembers about one task, attached to the task so it lives exactly as long.
///
/// `Sendable` because `identity` never changes and `state` is behind a lock.
private final class WebSocketTaskRecord: NSObject, Sendable {
    private struct State {
        var isStarted = false
        var isOpened = false
        var isClosed = false
    }

    private static let creation = OSAllocatedUnfairLock()

    /// The class object is a stable, unique address, which is all an association key needs to be.
    private static var key: UnsafeRawPointer {
        unsafeBitCast(Self.self, to: UnsafeRawPointer.self)
    }

    let identity: SocketIdentity
    private let state = OSAllocatedUnfairLock(initialState: State())

    private init(identity: SocketIdentity) {
        self.identity = identity
    }

    static func existing(on task: URLSessionWebSocketTask) -> WebSocketTaskRecord? {
        creation.withLock { objc_getAssociatedObject(task, key) as? Self }
    }

    static func of(_ task: URLSessionWebSocketTask, engine: SocketCaptureEngine) -> WebSocketTaskRecord {
        creation.withLock {
            if let existing = objc_getAssociatedObject(task, key) as? Self {
                return existing
            }
            let record = WebSocketTaskRecord(
                identity: engine.identity(
                    source: .webSocketTask,
                    url: webSocketURL(of: task),
                    fallbackName: "WebSocket"
                )
            )
            objc_setAssociatedObject(task, key, record, .OBJC_ASSOCIATION_RETAIN)
            return record
        }
    }

    /// URLSession rewrites `ws` and `wss` to `http` and `https` in a request it built from a URL.
    private static func webSocketURL(of task: URLSessionWebSocketTask) -> URL? {
        guard let url = task.originalRequest?.url ?? task.currentRequest?.url,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        switch components.scheme?.lowercased() {
        case "http": components.scheme = "ws"
        case "https": components.scheme = "wss"
        default: break
        }
        return components.url ?? url
    }

    /// Returns whether this is the first time, since a task can be resumed again after a suspend.
    func markStarted() -> Bool {
        state.withLock { state in
            defer { state.isStarted = true }
            return !state.isStarted
        }
    }

    /// Returns whether this is the first sign the socket really opened.
    func markOpened() -> Bool {
        state.withLock { state in
            defer { state.isOpened = true }
            return !state.isOpened
        }
    }

    /// Returns whether this is the first close, so a socket only ever reports one.
    func markClosed() -> Bool {
        state.withLock { state in
            defer { state.isClosed = true }
            return !state.isClosed
        }
    }
}
