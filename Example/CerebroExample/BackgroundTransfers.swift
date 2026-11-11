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

    /// What iOS wants called once every event from a relaunch has been delivered.
    @MainActor private static var finishEvents: (() -> Void)?

    /// Called with how far a large download has got, such as "Downloading 42%".
    @MainActor static var onProgress: ((String) -> Void)?

    /// Creates the session again, which is what makes iOS deliver transfers that finished while the app
    /// wasn't running. Call it at launch, after `Cerebro.start()`, so Cerebro sees the session too.
    static func reconnect() {
        session.getAllTasks { tasks in
            // A transfer outlives the app, so one started by an earlier launch can still be running.
            for task in tasks {
                print("Background transfer still running from an earlier launch:", task.originalRequest?.url ?? "")
            }
        }
    }

    /// Call from `application(_:handleEventsForBackgroundURLSession:completionHandler:)`.
    @MainActor static func handleEvents(completionHandler: @escaping () -> Void) {
        finishEvents = completionHandler
        reconnect()
    }

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
        private var reportedPercent: [Int: Int] = [:]

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

        /// Reports each whole percent of a download once, which is often enough to see it moving.
        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            guard totalBytesExpectedToWrite > 1_000_000 else { return }
            let percent = Int(totalBytesWritten * 100 / totalBytesExpectedToWrite)
            let isNew = lock.withLock { () -> Bool in
                guard reportedPercent[downloadTask.taskIdentifier] != percent else { return false }
                reportedPercent[downloadTask.taskIdentifier] = percent
                return true
            }
            if isNew {
                Task { @MainActor in BackgroundTransfers.onProgress?("Downloading \(percent)%") }
            }
        }

        func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
            Task { @MainActor in
                BackgroundTransfers.finishEvents?()
                BackgroundTransfers.finishEvents = nil
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            let continuation = lock.withLock { waiting.removeValue(forKey: task.taskIdentifier) }
            if continuation == nil {
                // Nothing is waiting, so the transfer was started by an earlier launch of the app.
                let status = (task.response as? HTTPURLResponse)?.statusCode
                print("Background transfer from an earlier launch finished:", status ?? error ?? "no response")
            }
            if let response = task.response, error == nil {
                continuation?.resume(returning: response)
            } else {
                continuation?.resume(throwing: error ?? URLError(.badServerResponse))
            }
        }
    }
}
