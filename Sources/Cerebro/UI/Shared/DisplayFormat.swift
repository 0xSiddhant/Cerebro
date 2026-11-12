import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// How the dashboard writes durations and sizes, in one place so every screen agrees.
enum DisplayFormat {
    private static let previewByteLimit = 400
    private static let hexPreviewByteLimit = 64

    private static let timeFormat = Date.VerbatimFormatStyle(
        format: """
            \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\
            \(second: .twoDigits).\(secondFraction: .fractional(3))
            """,
        timeZone: .current,
        calendar: .current
    )

    static func duration(_ seconds: TimeInterval) -> String {
        seconds < 1 ? "\(Int((seconds * 1000).rounded())) ms" : String(format: "%.2f s", seconds)
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    /// Installed memory, which is sold in powers of two, so 8 GB reads as 8 GB.
    static func memory(_ byteCount: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: byteCount), countStyle: .memory)
    }

    /// When a saved session started, short enough for a title, such as "11 Nov, 14:02".
    static func sessionStart(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }

    /// A transfer speed, from bytes per second.
    static func rate(_ bytesPerSecond: Double) -> String {
        bytes(Int64(bytesPerSecond.rounded())) + "/s"
    }

    /// The time of day on a 24-hour clock, to the millisecond, because frames can be that close together.
    static func time(_ date: Date) -> String {
        date.formatted(timeFormat)
    }

    /// The start of a body as text, or `nil` if it's binary. Stored bodies are already redacted.
    static func preview(of data: Data) -> String? {
        let start = data.prefix(previewByteLimit)
        guard !start.isEmpty, !start.contains(0) else { return nil }
        // A character of up to four bytes can be cut off at the limit, so allow for losing its start.
        let droppable = data.count > previewByteLimit ? 3 : 0
        return (0...droppable).lazy.compactMap { String(data: start.dropLast($0), encoding: .utf8) }.first
    }

    /// The start of a stored body: text if it's text, otherwise hex. Protobuf that wasn't decoded is
    /// always hex, because it can pass for text by chance.
    static func preview(of body: CapturedBody) -> String? {
        guard let data = body.data, !data.isEmpty else { return nil }
        if body.undecoded == nil, let text = preview(of: data) {
            return text
        }
        return BodyFormatter.hex(data.prefix(hexPreviewByteLimit))
    }

    /// What happened to a body's protobuf, if it has any.
    static func decodingLabel(of body: CapturedBody) -> String? {
        if body.isDecoded {
            return "decoded"
        }
        switch body.undecoded {
        case .noRule: return "proto, no rule"
        case .truncated: return "proto, too large to decode"
        case .failed: return "proto, couldn't be decoded"
        case nil: return nil
        }
    }

    static func status(of transaction: HTTPTransaction) -> String {
        switch transaction.outcome {
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        default: return transaction.response.map { String($0.statusCode) } ?? ""
        }
    }
}
