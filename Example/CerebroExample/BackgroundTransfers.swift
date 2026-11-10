import Foundation

/// A background session, with its delegate's callbacks turned into `async` for the samples.
///
/// Cerebro needs nothing from this code. A background session created after `Cerebro.start()` shows up in
/// the dashboard by itself, with its metrics but never its file.
enum BackgroundTransfers {
    private static let delegate = Delegate()

    // Background sessions only work through a delegate, and need one identifier per session.
    private static let session = URLSession(
        configuration: .background(withIdentifier: "io.github.0xsiddhant.CerebroExample.background"),
        delegate: delegate,
        delegateQueue: nil
    )

    static func download(from url: URL) async throws -> URLResponse {
        try await delegate.run(session.downloadTask(with: url))
    }

    /// Background uploads have to come from a file.
    static func upload(_ body: Data, to url: URL) async throws -> URLResponse {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try body.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        return try await delegate.run(session.uploadTask(with: request, fromFile: file))
    }

    /// Safety for `@unchecked Sendable`: `waiting` is only touched while holding `lock`.
    private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var waiting: [Int: CheckedContinuation<URLResponse, Error>] = [:]

        func run(_ task: URLSessionTask) async throws -> URLResponse {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock { waiting[task.taskIdentifier] = continuation }
                task.resume()
            }
        }

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {
            // A real app moves the file here, because iOS deletes it as soon as this returns.
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            let continuation = lock.withLock { waiting.removeValue(forKey: task.taskIdentifier) }
            if let response = task.response, error == nil {
                continuation?.resume(returning: response)
            } else {
                continuation?.resume(throwing: error ?? URLError(.badServerResponse))
            }
        }
    }
}
