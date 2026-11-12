import Foundation
@testable import CerebroCore

enum Fixtures {
    static func gzip(_ data: Data) throws -> Data {
        let deflated = try (data as NSData).compressed(using: .zlib) as Data
        return Data([0x1F, 0x8B, 0x08, 0, 0, 0, 0, 0, 0, 0xFF]) + deflated + Data(count: 8)
    }

    /// A gzip stream with a real trailer, which URLSession checks when it decodes a response.
    static func gzipWithTrailer(_ data: Data) throws -> Data {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        let trailer = [~crc, UInt32(data.count)].flatMap { value in
            (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) }
        }
        return try gzip(data).dropLast(8) + Data(trailer)
    }

    static func zlib(_ data: Data) throws -> Data {
        let deflated = try (data as NSData).compressed(using: .zlib) as Data
        return Data([0x78, 0x9C]) + deflated + Data(count: 4)
    }

    static func raw(_ data: Data, limit: Int = 1_000) -> RawBody {
        var body = RawBody(limit: limit)
        body.append(data)
        return body
    }

    static func context(contentType: String? = nil, direction: BodyContext.Direction = .response) -> BodyContext {
        BodyContext(
            url: URL(string: "https://example.com"),
            method: "GET",
            contentType: contentType,
            direction: direction
        )
    }

    static func event(_ text: String, id: String? = nil, type: String = "message") -> CapturedSSEEvent {
        CapturedSSEEvent(
            id: id,
            type: type,
            data: CapturedBody(content: .complete(Data(text.utf8)), byteCount: text.utf8.count),
            date: Date(timeIntervalSince1970: 2)
        )
    }

    /// An event stream's transaction. Pass `id` to make a later state of the same one.
    static func stream(
        id: UUID = UUID(),
        _ state: CapturedEventStream.State,
        events: [CapturedSSEEvent] = [],
        size: TransferSize? = nil
    ) -> HTTPTransaction {
        HTTPTransaction(
            id: id,
            request: CapturedRequest(
                url: URL(string: "https://example.com/feed"), method: "GET", startDate: Date(timeIntervalSince1970: 0)),
            response: CapturedResponse(
                statusCode: 200, mimeType: "text/event-stream", endDate: Date(timeIntervalSince1970: 1)),
            size: size,
            eventStream: CapturedEventStream(state: state, eventCount: events.count, events: events)
        )
    }

    static func transaction(status: Int = 200, path: String = "/") -> HTTPTransaction {
        HTTPTransaction(
            request: CapturedRequest(
                url: URL(string: "https://example.com\(path)"),
                method: "GET",
                startDate: Date(timeIntervalSince1970: 0)
            ),
            response: CapturedResponse(statusCode: status, endDate: Date(timeIntervalSince1970: 1))
        )
    }
}
