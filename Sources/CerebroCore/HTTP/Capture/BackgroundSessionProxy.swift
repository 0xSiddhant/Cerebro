import Foundation
import os

/// Stands in for the app's delegate on a background session. The transfer runs in a system process, so
/// the delegate's callbacks are the only place it can be seen.
///
/// It reads metrics and completion, and everything else goes straight to the app's delegate, so a
/// downloaded file is never touched. These callbacks run on the app's delegate queue, so this only
/// stores and hands off.
///
/// Safety for `@unchecked Sendable`: `appDelegate` never changes, and `pending` is behind a lock.
final class BackgroundSessionProxy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private struct Completion: Sendable {
        let task: URLSessionTask
        let error: (any Error)?
        let date: Date
    }

    private struct Pending: Sendable {
        var metrics: URLSessionTaskMetrics?
        var completion: Completion?
    }

    /// Held strongly, as `URLSession` holds its delegate. `AnyObject` and not `NSObject`, because the
    /// delegate may be an `NSProxy`, and it's reached by selector so one that never declared the protocol
    /// behaves as it would without Cerebro.
    let appDelegate: AnyObject?

    private let pending = OSAllocatedUnfairLock<[Int: Pending]>(initialState: [:])

    init(appDelegate: AnyObject?) {
        self.appDelegate = appDelegate
    }

    override func responds(to selector: Selector?) -> Bool {
        super.responds(to: selector) || appDelegateResponds(to: selector)
    }

    override func forwardingTarget(for selector: Selector?) -> Any? {
        appDelegateResponds(to: selector) ? appDelegate : nil
    }

    private func appDelegateResponds(to selector: Selector?) -> Bool {
        guard let selector else { return false }
        return appDelegate?.responds(to: selector) == true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        record(metrics, for: task)
        appDelegate?.urlSession?(session, task: task, didFinishCollecting: metrics)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        recordCompletion(of: task, error: error)
        appDelegate?.urlSession?(session, task: task, didCompleteWithError: error)
    }

    private func record(_ metrics: URLSessionTaskMetrics, for task: URLSessionTask) {
        let id = task.taskIdentifier
        let completion = pending.withLock { pending -> Completion? in
            guard let completion = pending[id]?.completion else {
                pending[id, default: Pending()].metrics = metrics
                return nil
            }
            pending[id] = nil
            return completion
        }
        if let completion {
            submit(completion, metrics: metrics)
        }
    }

    /// Metrics have always arrived first, but nothing promises that, so a completion waits briefly for them.
    private func recordCompletion(of task: URLSessionTask, error: (any Error)?) {
        let id = task.taskIdentifier
        let completion = Completion(task: task, error: error, date: Date())
        let metrics = pending.withLock { pending -> URLSessionTaskMetrics? in
            if let metrics = pending.removeValue(forKey: id)?.metrics {
                return metrics
            }
            pending[id] = Pending(completion: completion)
            return nil
        }
        if let metrics {
            submit(completion, metrics: metrics)
            return
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + CustomURLProtocol.metricsGrace) { [self] in
            if let waiting = pending.withLock({ $0.removeValue(forKey: id)?.completion }) {
                submit(waiting, metrics: nil)
            }
        }
    }

    /// Times come from the metrics, because a transfer can start in an earlier launch. The request is the
    /// last hop's, so the URL, status, timing and connection all describe the same one.
    private func submit(_ completion: Completion, metrics: URLSessionTaskMetrics?) {
        let task = completion.task
        guard let engine = HTTPCaptureEngine.active, let request = task.currentRequest ?? task.originalRequest else {
            return
        }
        engine.submit(
            RawExchange(
                id: UUID(),
                request: request,
                requestBody: nil,
                response: task.response,
                responseBody: nil,
                error: completion.error,
                metrics: metrics,
                startDate: metrics?.taskInterval.start ?? completion.date,
                endDate: metrics?.taskInterval.end ?? completion.date
            )
        )
    }
}
