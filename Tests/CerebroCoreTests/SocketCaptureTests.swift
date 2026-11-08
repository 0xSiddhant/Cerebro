import Foundation
import Network
import ObjectiveC
import Testing
import os
@testable import CerebroCore

extension SocketConnection {
    fileprivate var frames: [SocketFrame] {
        timeline.compactMap {
            if case .frame(let frame) = $0 { return frame }
            return nil
        }
    }

    fileprivate var events: [SocketEvent] {
        timeline.compactMap {
            if case .event(let event, _) = $0 { return event }
            return nil
        }
    }
}

private func text(of frame: SocketFrame?) -> String? {
    frame?.payload?.data.flatMap { String(data: $0, encoding: .utf8) }
}

private func webSocketTask(to url: URL) -> URLSessionWebSocketTask {
    URLSession(configuration: .ephemeral).webSocketTask(with: url)
}

private func send(_ message: URLSessionWebSocketTask.Message, on task: URLSessionWebSocketTask) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        task.send(message) { error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }
}

private func receive(on task: URLSessionWebSocketTask) async throws -> URLSessionWebSocketTask.Message {
    try await withCheckedThrowingContinuation { continuation in
        task.receive { continuation.resume(with: $0) }
    }
}

private final class SlowDecoder: BodyDecoder {
    let ranOffTheMainThread = OSAllocatedUnfairLock(initialState: false)

    func decode(_ body: Data, context: BodyContext) -> Data? {
        ranOffTheMainThread.withLock { $0 = !Thread.isMainThread }
        Thread.sleep(forTimeInterval: 0.3)
        return nil
    }
}

private func withServer(_ test: (URL) async throws -> Void) async throws {
    let server = try LocalWebSocketServer()
    let url = try await server.start()
    defer { server.stop() }
    try await test(url)
}

extension CaptureTests {
    @Suite struct WebSocketTasks {
        @Test func bothAPIFormsAreCapturedInOrder() async throws {
            try await withServer { url in
                try await withCapture { harness in
                    let task = webSocketTask(to: url)
                    task.resume()

                    try await send(.string("handler"), on: task)
                    _ = try await receive(on: task)
                    try await task.send(.data(Data([1, 2, 3])))
                    _ = try await task.receive()

                    let socket = try await harness.socket { $0.frameCount == 4 }
                    #expect(socket.source == .webSocketTask)
                    #expect(socket.name == url.absoluteString)
                    #expect(socket.status == .open)
                    #expect(socket.events.first == .opened)
                    #expect(socket.frames.map(\.direction) == [.sent, .received, .sent, .received])
                    #expect(socket.frames.map(\.kind) == [.text, .text, .binary, .binary])
                    #expect(text(of: socket.frames.first) == "handler")
                    #expect(socket.frames.last?.payload?.data == Data([1, 2, 3]))
                }
            }
        }

        @Test func theAppStillGetsItsMessages() async throws {
            try await withServer { url in
                try await withCapture { _ in
                    let task = webSocketTask(to: url)
                    task.resume()

                    try await task.send(.string("echo me"))

                    guard case .string(let reply) = try await task.receive() else {
                        Issue.record("expected text")
                        return
                    }
                    #expect(reply == "echo me")
                }
            }
        }

        @Test func pingAndPongAreEvents() async throws {
            try await withServer { url in
                try await withCapture { harness in
                    let task = webSocketTask(to: url)
                    task.resume()

                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                        task.sendPing { error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                    }

                    let socket = try await harness.socket { $0.events.contains(.pong) }
                    #expect(socket.events == [.opened, .ping, .pong])
                }
            }
        }

        @Test func closingWithACodeRecordsItOnce() async throws {
            try await withServer { url in
                try await withCapture { harness in
                    let task = webSocketTask(to: url)
                    task.resume()
                    try await task.send(.string("x"))
                    _ = try await task.receive()

                    task.cancel(with: .goingAway, reason: Data("done".utf8))
                    await #expect(throws: (any Error).self) { try await task.receive() }

                    let socket = try await harness.socket { $0.status == .closed }
                    try await Task.sleep(for: .milliseconds(100))
                    let events = try await harness.socket { $0.id == socket.id }.events
                    #expect(events == [.opened, .closed(code: 1001, reason: "done")])
                }
            }
        }

        @Test func aCloseStartedByTheServerIsReadAfterReceiveFails() async throws {
            try await withServer { url in
                try await withCapture { harness in
                    let task = webSocketTask(to: url)
                    task.resume()
                    try await task.send(.string("close"))

                    await #expect(throws: (any Error).self) { try await task.receive() }

                    let socket = try await harness.socket { $0.status == .closed }
                    #expect(socket.events.last == .closed(code: 4001, reason: "bye"))
                }
            }
        }

        @Test func plainCancelIsAClose() async throws {
            try await withServer { url in
                try await withCapture { harness in
                    let task = webSocketTask(to: url)
                    task.resume()
                    try await task.send(.string("x"))
                    _ = try await task.receive()

                    task.cancel()

                    let socket = try await harness.socket { $0.status == .closed }
                    #expect(socket.events.last == .closed(code: nil, reason: nil))
                }
            }
        }

        @Test func aFailedConnectionIsReported() async throws {
            try await withCapture { harness in
                guard let unreachable = URL(string: "ws://127.0.0.1:9") else { return }
                let task = webSocketTask(to: unreachable)
                task.resume()

                await #expect(throws: (any Error).self) { try await task.receive() }

                let socket = try await harness.socket { $0.status == .failed }
                #expect(socket.frameCount == 0)
            }
        }

        @Test func eachTaskIsItsOwnSocket() async throws {
            try await withServer { url in
                try await withCapture { harness in
                    for _ in 0..<2 {
                        let task = webSocketTask(to: url)
                        task.resume()
                        try await task.send(.string("x"))
                        _ = try await task.receive()
                    }

                    _ = try await harness.socket { $0.frameCount == 2 }
                    try await Task.sleep(for: .milliseconds(50))
                    #expect(await harness.runtime.socketStore.connections.count == 2)
                }
            }
        }

        @Test func stoppingPutsTheOriginalMethodsBack() async throws {
            let selector = NSSelectorFromString("sendMessage:completionHandler:")
            let taskClass: AnyClass = try type(of: webSocketTask(to: #require(URL(string: "ws://localhost"))))
            let before = class_getMethodImplementation(taskClass, selector)

            try await withCapture { _ in
                #expect(class_getMethodImplementation(taskClass, selector) != before)
            }

            #expect(class_getMethodImplementation(taskClass, selector) == before)
        }

        @Test func aRedactedQueryNeverReachesTheName() async throws {
            try await withServer { url in
                let rules = RedactionRules(queryParameters: ["token"])
                let configuration = CerebroConfiguration(consoleLevel: .off, redaction: rules)
                try await withCapture(configuration) { harness in
                    let secret = try #require(URL(string: url.absoluteString + "/?token=secret"))
                    let task = webSocketTask(to: secret)
                    task.resume()
                    try await task.send(.string("x"))

                    let socket = try await harness.socket { $0.frameCount == 1 }
                    #expect(!socket.name.contains("secret"))
                    #expect(socket.name.contains(Redactor.marker) || socket.name.contains("redacted"))
                }
            }
        }
    }

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

    @Suite struct Bridge {
        @Test func framesAndEventsReachTheStore() async throws {
            try await withCapture { harness in
                let connection = ExternalNetworkBridge.Connection(name: "Starscream")

                ExternalNetworkBridge.log(.opened, on: connection)
                ExternalNetworkBridge.log(.text("hello"), .sent, on: connection)
                ExternalNetworkBridge.log(.binary(Data([9])), .received, on: connection)
                ExternalNetworkBridge.log(.closed(code: 1000, reason: "bye"), on: connection)

                let socket = try await harness.socket { $0.status == .closed }
                #expect(socket.source == .external)
                #expect(socket.name == "Starscream")
                #expect(socket.frameCount == 2)
                #expect(socket.events == [.opened, .closed(code: 1000, reason: "bye")])
            }
        }

        @Test func aURLNamesTheSocketWhenThereIsOne() async throws {
            try await withCapture { harness in
                let url = try #require(URL(string: "wss://example.com/feed"))

                ExternalNetworkBridge.log(.opened, on: ExternalNetworkBridge.Connection(name: "Feed", url: url))

                let socket = try await harness.socket { $0.status == .open }
                #expect(socket.name == "wss://example.com/feed")
            }
        }

        @Test func loggingDoesntWaitForThePipelineOrRunItOnTheMainThread() async throws {
            let decoder = SlowDecoder()
            let configuration = CerebroConfiguration(consoleLevel: .off, decoders: [decoder])
            try await withCapture(configuration) { harness in
                let connection = ExternalNetworkBridge.Connection(name: "Slow")
                let clock = ContinuousClock()

                let elapsed = await MainActor.run {
                    clock.measure { ExternalNetworkBridge.log(.text("x"), .sent, on: connection) }
                }

                #expect(elapsed < .milliseconds(150))
                _ = try await harness.socket { $0.frameCount == 1 }
                #expect(decoder.ranOffTheMainThread.withLock { $0 })
            }
        }

        @Test func doesNothingWhileCerebroIsOff() {
            #expect(SocketCaptureEngine.active == nil)

            ExternalNetworkBridge.log(.opened, on: ExternalNetworkBridge.Connection(name: "Off"))
        }
    }
}
