import Foundation

/// The real network session behind captured requests, and the one place its callbacks arrive.
///
/// It's never invalidated. A request can pass `canInit` just as Cerebro stops, and creating a task on
/// an invalidated session throws an exception that would crash the app.
///
/// Safety for `@unchecked Sendable`: `tasks` is only touched on `queue`, which is serial and is also
/// the session's delegate queue.
final class CaptureSession: NSObject, @unchecked Sendable {
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "io.github.0xsiddhant.cerebro.capture"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    private let configuration: URLSessionConfiguration
    private lazy var session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    private var tasks: [Int: CustomURLProtocol] = [:]

    /// `configuration` must come from a getter that isn't exchanged, or this session would capture itself.
    init(configuration: URLSessionConfiguration) {
        self.configuration = configuration
    }

    /// Runs work on the same queue as every delegate callback.
    func perform(_ work: @escaping @Sendable () -> Void) {
        queue.addOperation(work)
    }

    /// Runs work on that queue after a delay.
    func perform(after delay: DispatchTimeInterval, _ work: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [self] in perform(work) }
    }

    /// Call on `queue`.
    func makeTask(for request: URLRequest, spooledFile: URL?, owner: CustomURLProtocol) -> URLSessionTask {
        let task: URLSessionTask
        if let spooledFile {
            task = session.uploadTask(with: request, fromFile: spooledFile)
        } else {
            task = session.dataTask(with: request)
        }
        tasks[task.taskIdentifier] = owner
        return task
    }
}

extension CaptureSession: URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        tasks[dataTask.taskIdentifier]?.didReceive(response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        tasks[dataTask.taskIdentifier]?.didReceive(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // The app's own session follows the redirect, so its delegate still gets a say. Answering
        // here is what delivers the 3xx, so the answer waits until the app's session has decided.
        guard let owner = tasks[task.taskIdentifier] else {
            completionHandler(nil)
            return
        }
        owner.wasRedirected(to: request, by: response) { completionHandler(nil) }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard let owner = tasks[task.taskIdentifier] else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        owner.didReceive(challenge, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        tasks[task.taskIdentifier]?.didCollect(metrics)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        tasks.removeValue(forKey: task.taskIdentifier)?.didComplete(error: error)
    }
}
