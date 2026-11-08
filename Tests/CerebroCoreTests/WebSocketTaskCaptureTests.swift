import Foundation
import ObjectiveC
import Testing
@testable import CerebroCore

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
                    #expect(socket.events == [.stateChanged("Connecting"), .opened])
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
                    #expect(socket.events == [.stateChanged("Connecting"), .ping, .opened, .pong])
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
                    #expect(events == [.stateChanged("Connecting"), .opened, .closed(code: 1001, reason: "done")])
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
                #expect(!socket.events.contains(.opened))
            }
        }

        @Test func aRefusedUpgradeIsNeverOpen() async throws {
            let refuse: CaptureHarness.Handler = { _ in LocalHTTPServer.Response(status: 401, reason: "Unauthorized") }
            try await withCapture(handler: refuse) { harness in
                let url = try #require(
                    URL(string: harness.baseURL.absoluteString.replacingOccurrences(of: "http", with: "ws")))
                let task = webSocketTask(to: url)
                task.resume()

                await #expect(throws: (any Error).self) { try await task.receive() }

                let socket = try await harness.socket { $0.status == .failed }
                #expect(!socket.events.contains(.opened))
            }
        }

        @Test func aFailedSendStillShows() async throws {
            try await withCapture { harness in
                let unreachable = try #require(URL(string: "ws://127.0.0.1:9"))
                let task = webSocketTask(to: unreachable)
                task.resume()

                await #expect(throws: (any Error).self) { try await task.send(.string("lost")) }

                let socket = try await harness.socket { $0.frameCount == 1 }
                #expect(socket.frames.first?.didFail == true)
                #expect(text(of: socket.frames.first) == "lost")
                #expect(socket.bytesSent == 0)
            }
        }

        @Test func aRequestBuiltWithAWebSocketSchemeKeepsIt() async throws {
            try await withServer { url in
                try await withCapture { harness in
                    let session = URLSession(configuration: .ephemeral)
                    let task = session.webSocketTask(with: URLRequest(url: url))
                    task.resume()
                    try await task.send(.string("x"))

                    let socket = try await harness.socket { $0.frameCount == 1 }
                    #expect(socket.name == url.absoluteString)
                    #expect(socket.name.hasPrefix("ws://"))
                }
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
}
