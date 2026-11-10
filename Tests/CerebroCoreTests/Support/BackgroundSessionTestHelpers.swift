import Foundation

/// Stands in for the app's delegate, and remembers what reached it.
final class SpyDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    var calls: [String] {
        lock.withLock { names }
    }

    private func note(_ name: String) {
        lock.withLock { names.append(name) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        note("file:\(FileManager.default.fileExists(atPath: location.path))")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        note("metrics")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        note("complete")
    }
}

/// Implements a callback without declaring the protocol, which Objective-C delegates can do.
final class UndeclaredDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var completions: Int {
        lock.withLock { count }
    }

    @objc(URLSession:task:didCompleteWithError:)
    func finished(_ session: URLSession, task: URLSessionTask, error: (any Error)?) {
        lock.withLock { count += 1 }
    }
}

/// Runs a request and keeps its real task and metrics, because neither can be made by hand.
final class TransferRecorder: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var collected: URLSessionTaskMetrics?
    private var continuation: CheckedContinuation<URLSessionTaskMetrics?, Never>?

    func run(_ task: URLSessionTask) async -> URLSessionTaskMetrics? {
        await withCheckedContinuation { continuation in
            lock.withLock { self.continuation = continuation }
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.withLock { collected = metrics }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (metrics, continuation) = lock.withLock { (collected, self.continuation) }
        continuation?.resume(returning: metrics)
    }
}
