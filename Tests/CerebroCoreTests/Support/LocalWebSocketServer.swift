import Foundation
import Network
import os

/// A real WebSocket server on the loopback interface. It echoes every message, answers pings, and
/// closes with code 4001 and the reason "bye" when it receives the text "close".
final class LocalWebSocketServer: Sendable {
    private let listener: NWListener

    init() throws {
        let options = NWProtocolWebSocket.Options()
        options.autoReplyPing = true
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
        parameters.requiredInterfaceType = .loopback
        listener = try NWListener(using: parameters, on: .any)
    }

    /// Starts listening and returns the server's URL.
    func start() async throws -> URL {
        let port: UInt16 = await withCheckedContinuation { continuation in
            let listener = listener
            let resumed = OSAllocatedUnfairLock(initialState: false)
            listener.newConnectionHandler = { [self] connection in
                connection.start(queue: .global())
                echo(on: connection)
            }
            listener.stateUpdateHandler = { state in
                guard case .ready = state else { return }
                let isFirst = resumed.withLock { wasResumed -> Bool in
                    defer { wasResumed = true }
                    return !wasResumed
                }
                if isFirst {
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                }
            }
            listener.start(queue: .global())
        }
        return try requireWebSocketURL("ws://127.0.0.1:\(port)")
    }

    func stop() {
        listener.cancel()
    }

    private func echo(on connection: NWConnection) {
        connection.receiveMessage { [self] data, context, _, error in
            guard error == nil,
                let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                    as? NWProtocolWebSocket.Metadata
            else { return }
            if data == Data("close".utf8) {
                close(connection)
                return
            }
            if metadata.opcode == .text || metadata.opcode == .binary {
                send(data, opcode: metadata.opcode, on: connection)
            }
            echo(on: connection)
        }
    }

    private func send(_ data: Data?, opcode: NWProtocolWebSocket.Opcode, on connection: NWConnection) {
        let context = NWConnection.ContentContext(
            identifier: "echo",
            metadata: [NWProtocolWebSocket.Metadata(opcode: opcode)]
        )
        connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
    }

    private func close(_ connection: NWConnection) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
        metadata.closeCode = .privateCode(4001)
        let context = NWConnection.ContentContext(identifier: "close", metadata: [metadata])
        connection.send(content: Data("bye".utf8), contentContext: context, isComplete: true, completion: .idempotent)
    }
}

private func requireWebSocketURL(_ string: String) throws -> URL {
    guard let url = URL(string: string) else { throw URLError(.badURL) }
    return url
}
