import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// How the dashboard writes durations and sizes, in one place so every screen agrees.
enum DisplayFormat {
    static func duration(_ seconds: TimeInterval) -> String {
        seconds < 1 ? "\(Int((seconds * 1000).rounded())) ms" : String(format: "%.2f s", seconds)
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func status(of transaction: HTTPTransaction) -> String {
        switch transaction.outcome {
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        default: return transaction.response.map { String($0.statusCode) } ?? ""
        }
    }
}
