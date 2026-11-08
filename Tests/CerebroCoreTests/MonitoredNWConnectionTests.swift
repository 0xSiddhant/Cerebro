import Foundation
import Network
import Testing
import os
@testable import CerebroCore

/// Collects the states a connection goes through, which arrive on another thread.
private final class StateLog: Sendable {
    private let states = OSAllocatedUnfairLock<[NWConnection.State]>(initialState: [])

    func add(_ state: NWConnection.State) {
        states.withLock { $0.append(state) }
    }

    func wait(for matches: @Sendable (NWConnection.State) -> Bool) async -> Bool {
        for _ in 0..<300 {
            if states.withLock({ $0.contains(where: matches) }) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }
}

extension CaptureTests {
    @Suite struct MonitoredConnections {
        private func parameters() -> NWParameters {
            let parameters = NWParameters.tcp
            parameters.defaultProtocolStack.applicationProtocols.insert(NWProtocolWebSocket.Options(), at: 0)
            return parameters
        }

        private var textContext: NWConnection.ContentContext {
            NWConnection.ContentContext(identifier: "text", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        }

        private func start(_ connection: MonitoredNWConnection) async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                connection.stateUpdateHandler = { state in
                    if case .ready = state {
                        continuation.resume()
                    }
                }
                connection.start(queue: .global())
            }
        }

        private func exchange(_ message: String, on connection: MonitoredNWConnection) async -> Data? {
            await withCheckedContinuation { continuation in
                connection.send(content: Data(message.utf8), contentContext: textContext, completion: .idempotent)
                connection.receiveMessage { data, _, _, _ in
                    continuation.resume(returning: data)
                }
            }
        }

        @Test func recordsStateAndFramesAndStillForwards() async throws {
            try await withServer { url in
                try await withCapture { harness in
                    let connection = MonitoredNWConnection(to: .url(url), using: parameters())
                    await start(connection)

                    let reply = await exchange("hi", on: connection)

                    #expect(reply == Data("hi".utf8))
                    let socket = try await harness.socket { $0.frameCount == 2 }
                    #expect(socket.source == .nwConnection)
                    #expect(socket.status == .open)
                    #expect(socket.events.contains(.opened))
                    #expect(socket.frames.map(\.direction) == [.sent, .received])
                    #expect(socket.frames.map(\.kind) == [.text, .text])
                    #expect(text(of: socket.frames.first) == "hi")

                    connection.cancel()
                    let closed = try await harness.socket { $0.status == .closed }
                    #expect(closed.events.last == .closed(code: nil, reason: nil))
                }
            }
        }

        @Test func theAppsHandlerStillRunsAfterTheWrapperIsReleased() async throws {
            try await withServer { url in
                try await withCapture { harness in
                    let states = StateLog()
                    var connection: MonitoredNWConnection? = MonitoredNWConnection(to: .url(url), using: parameters())
                    connection?.stateUpdateHandler = { states.add($0) }
                    connection?.start(queue: .global())
                    #expect(await states.wait { if case .ready = $0 { true } else { false } })

                    connection?.cancel()
                    connection = nil

                    #expect(await states.wait { if case .cancelled = $0 { true } else { false } })
                    _ = try await harness.socket { $0.status == .closed }
                }
            }
        }

        @Test func wrappingKeepsAHandlerAlreadySet() async throws {
            try await withServer { url in
                try await withCapture { _ in
                    let states = StateLog()
                    let plain = NWConnection(to: .url(url), using: parameters())
                    plain.stateUpdateHandler = { states.add($0) }

                    let monitored = MonitoredNWConnection(wrapping: plain)
                    monitored.start(queue: .global())

                    #expect(monitored.stateUpdateHandler != nil)
                    #expect(await states.wait { if case .ready = $0 { true } else { false } })
                    monitored.cancel()
                }
            }
        }

        @Test func aSendFailingAfterCancelLeavesTheSocketClosed() async throws {
            try await withServer { url in
                try await withCapture { harness in
                    let connection = MonitoredNWConnection(to: .url(url), using: parameters())
                    await start(connection)
                    connection.cancel()
                    _ = try await harness.socket { $0.status == .closed }

                    connection.send(
                        content: Data("late".utf8), contentContext: textContext, completion: .contentProcessed { _ in })
                    let socket = try await harness.socket { $0.frameCount == 1 }

                    #expect(socket.status == .closed)
                    #expect(socket.frames.first?.didFail == true)
                    #expect(!socket.events.contains { if case .failed = $0 { true } else { false } })
                }
            }
        }

        @Test func onlyForwardsWhileCerebroIsOff() async throws {
            #expect(SocketCaptureEngine.active == nil)
            try await withServer { url in
                let connection = MonitoredNWConnection(to: .url(url), using: parameters())
                await start(connection)

                let reply = await exchange("off", on: connection)

                #expect(reply == Data("off".utf8))
                connection.cancel()
            }
        }

        @Test func stateHandlerCanBeReadBack() {
            let connection = MonitoredNWConnection(host: "127.0.0.1", port: 9, using: .tcp)
            #expect(connection.stateUpdateHandler == nil)

            connection.stateUpdateHandler = { _ in }

            #expect(connection.stateUpdateHandler != nil)
        }
    }
}
