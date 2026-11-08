import Foundation
import Testing
import os
@testable import CerebroCore

private final class SlowDecoder: BodyDecoder {
    let ranOffTheMainThread = OSAllocatedUnfairLock(initialState: false)

    func decode(_ body: Data, context: BodyContext) -> Data? {
        ranOffTheMainThread.withLock { $0 = !Thread.isMainThread }
        Thread.sleep(forTimeInterval: 0.3)
        return nil
    }
}

extension CaptureTests {
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

        @Test(arguments: [Int.max, -1])
        func extremeBodyLimitsDontCrash(limit: Int) async throws {
            let configuration = CerebroConfiguration(consoleLevel: .off, bodyLimit: limit)
            try await withCapture(configuration) { harness in
                ExternalNetworkBridge.log(.text("x"), .sent, on: ExternalNetworkBridge.Connection(name: "Limit"))

                let socket = try await harness.socket { $0.frameCount == 1 }
                #expect(socket.frames.first?.byteCount == 1)
            }
        }

        @Test func aBurstAcrossSocketsKeepsEveryCloseAndTotal() async throws {
            let configuration = CerebroConfiguration(consoleLevel: .off, socketFrameLimit: 5)
            try await withCapture(configuration) { harness in
                let sockets = (0..<20).map { ExternalNetworkBridge.Connection(name: "Socket \($0)") }

                for socket in sockets {
                    for _ in 0..<20 {
                        ExternalNetworkBridge.log(.text("x"), .sent, on: socket)
                    }
                    ExternalNetworkBridge.log(.closed(code: 1000, reason: nil), on: socket)
                }

                for socket in sockets {
                    let stored = try await harness.socket { $0.name == socket.name && $0.status == .closed }
                    #expect(stored.frameCount == 20)
                    #expect(stored.bytesSent == 20)
                }
            }
        }

        @Test func doesNothingWhileCerebroIsOff() {
            #expect(SocketCaptureEngine.active == nil)

            ExternalNetworkBridge.log(.opened, on: ExternalNetworkBridge.Connection(name: "Off"))
        }
    }
}
