import Foundation
import Testing
@testable import CerebroCore

extension SocketConnection {
    var frames: [SocketFrame] {
        timeline.compactMap {
            if case .frame(let frame) = $0 { return frame }
            return nil
        }
    }

    var events: [SocketEvent] {
        timeline.compactMap {
            if case .event(let event, _) = $0 { return event }
            return nil
        }
    }
}

func text(of frame: SocketFrame?) -> String? {
    frame?.payload?.data.flatMap { String(data: $0, encoding: .utf8) }
}

func withServer(_ test: (URL) async throws -> Void) async throws {
    let server = try LocalWebSocketServer()
    let url = try await server.start()
    defer { server.stop() }
    try await test(url)
}
