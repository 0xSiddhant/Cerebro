import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// How the dashboard writes durations and sizes, in one place so every screen agrees.
enum DisplayFormat {
    private static let previewByteLimit = 400

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

    /// The time of day on a 24-hour clock, to the millisecond, because frames can be that close together.
    static func time(_ date: Date) -> String {
        date.formatted(timeFormat)
    }

    /// The start of a body as text, or `nil` if it's binary. Stored bodies are already redacted.
    static func preview(of data: Data) -> String? {
        let start = data.prefix(previewByteLimit)
        guard !start.isEmpty, !start.contains(0) else { return nil }
        // A character of up to four bytes can be cut off at the limit, so allow for losing its start.
        return (0...3).lazy.compactMap { String(data: start.dropLast($0), encoding: .utf8) }.first
    }

    static func status(of transaction: HTTPTransaction) -> String {
        switch transaction.outcome {
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        default: return transaction.response.map { String($0.statusCode) } ?? ""
        }
    }
}
