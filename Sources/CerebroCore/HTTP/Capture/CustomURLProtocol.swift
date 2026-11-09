import Foundation

/// Takes over a request, runs it through Cerebro's own session and records what happened. The app
/// always gets each callback first, and the record is handed off afterwards.
///
/// Safety for `@unchecked Sendable`: `engine` never changes, `isStopped` is guarded by `clientLock`,
/// and the rest of the mutable state below is only touched on the owning `CaptureSession`'s serial
/// queue. The system calls `startLoading` and `stopLoading` on other threads, so both hop onto that
/// queue for everything except `isStopped`.
class CustomURLProtocol: URLProtocol, @unchecked Sendable {
    /// Which of the engine's sessions a request runs through.
    enum SessionKind {
        case standard
        case ephemeral
    }

    private static let handledKey = "io.github.0xsiddhant.cerebro.handled"

    /// Connection-level challenges, whose answer comes back through `URLAuthenticationChallengeSender`.
    /// HTTP logins never get an answer back from a URLProtocol's client, so forwarding one hangs.
    private static let forwardedChallenges: Set<String> = [
        NSURLAuthenticationMethodServerTrust,
        NSURLAuthenticationMethodClientCertificate,
    ]

    /// How long to wait for metrics that haven't arrived by completion, which some OS versions do.
    static let metricsGrace: DispatchTimeInterval = .milliseconds(250)

    /// How long a 3xx waits for the app's session to follow it. Following calls `stopLoading` at once,
    /// but refusing sends no signal, so the 3xx is delivered as the final response once this passes.
    private static let redirectGrace: DispatchTimeInterval = .milliseconds(500)

    class var sessionKind: SessionKind { .standard }

    private let engine: HTTPCaptureEngine?
    /// Held across every client call and while stopping, so no callback can follow `stopLoading`.
    /// It's recursive in case a client call ever re-enters `stopLoading` on the same thread.
    private let clientLock = NSRecursiveLock()
    private var isStopped = false
    private var runningTask: URLSessionTask?
    private var isRedirected = false
    private var releaseRedirect: (() -> Void)?
    private var spooledFile: URL?
    private var challengeHandler: ((URLSession.AuthChallengeDisposition, URLCredential?) -> Void)?

    private let id = UUID()
    private let startDate = Date()
    private var requestBody: RawBody
    private var response: URLResponse?
    private var responseBody: RawBody?
    private var metrics: URLSessionTaskMetrics?
    private var completion: (error: (any Error)?, date: Date)?
    private var isRecorded = false

    override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: (any URLProtocolClient)?) {
        // Held for the request's whole life, so it can still be cancelled after `stop`.
        engine = HTTPCaptureEngine.active
        requestBody = RawBody(limit: engine?.bodyLimit ?? 0)
        super.init(request: request, cachedResponse: cachedResponse, client: client)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard HTTPCaptureEngine.active != nil,
            let scheme = request.url?.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else { return false }
        return property(forKey: handledKey, in: request) == nil
    }

    override class func canInit(with task: URLSessionTask) -> Bool {
        guard !(task is URLSessionWebSocketTask), !(task is URLSessionStreamTask),
            let request = task.currentRequest
        else { return false }
        return canInit(with: request)
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    private var session: CaptureSession? {
        engine?.session(for: Self.sessionKind)
    }

    override func startLoading() {
        guard let engine, let session else {
            sendToClient { $0.urlProtocol(self, didFailWithError: URLError(.cancelled)) }
            return
        }
        let storesResponseBody = !(task is URLSessionDownloadTask)
        session.perform { [self] in
            responseBody = storesResponseBody ? RawBody(limit: engine.bodyLimit) : nil
        }
        guard request.httpBodyStream != nil else {
            session.perform { [self] in begin(with: nil) }
            return
        }
        // A stream can block, so it never runs on the queue every request shares.
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let body = request.httpBodyStream.map { RequestBodyReader.read($0, limit: engine.bodyLimit) }
            session.perform { [self] in begin(with: body) }
        }
    }

    override func stopLoading() {
        // Set here, not on the queue, so a callback already waiting there can't reach the client.
        clientLock.withLock { isStopped = true }
        session?.perform { [self] in
            challengeHandler?(.cancelAuthenticationChallenge, nil)
            challengeHandler = nil
            runningTask?.cancel()
            endRedirectWait()
        }
    }

    /// The one way to reach the client. URLSession uses the same client for every hop of a redirect, so
    /// a callback sent after `stopLoading` lands on the next load. A finish with no response there
    /// makes `URLSession.data(for:)` trap, which would crash the app.
    @discardableResult
    private func sendToClient(_ send: (any URLProtocolClient) -> Void) -> Bool {
        clientLock.withLock {
            guard !isStopped, let client else { return false }
            send(client)
            return true
        }
    }

    private func begin(with body: RequestBodyReader.Output?) {
        if let body {
            requestBody = body.captured
            spooledFile = body.spooledFile
        }
        if let error = body?.error {
            sendToClient { $0.urlProtocol(self, didFailWithError: error) }
            completion = (error, Date())
            finish()
            return
        }
        guard !clientLock.withLock({ isStopped }), let session,
            let outgoing = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest
        else {
            spooledFile.map(RequestBodyReader.remove)
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: outgoing)
        outgoing.httpBodyStream = nil
        if spooledFile == nil, let body {
            outgoing.httpBody = body.captured.data
        }
        let task = session.makeTask(for: outgoing as URLRequest, spooledFile: spooledFile, owner: self)
        runningTask = task
        task.resume()
    }

    // MARK: - Callbacks from CaptureSession, on its queue

    func didReceive(_ response: URLResponse) {
        self.response = response
        sendToClient { $0.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
    }

    func didReceive(_ data: Data) {
        sendToClient { $0.urlProtocol(self, didLoad: data) }
        responseBody?.append(data)
    }

    /// Hands the decision to the app's session. If it follows the redirect, it stops this load and starts
    /// a new one. If it refuses, the 3xx is what it delivers, so `release` lets that continue. It can't
    /// run sooner, because a 3xx that arrives while the app's session is following either replaces the
    /// real response or finishes the next load with no response, which crashes `URLSession.data(for:)`.
    func wasRedirected(to newRequest: URLRequest, by response: HTTPURLResponse, release: @escaping () -> Void) {
        self.response = response
        isRedirected = true
        guard let next = (newRequest as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            release()
            return
        }
        URLProtocol.removeProperty(forKey: Self.handledKey, in: next)
        let wasSent = sendToClient {
            $0.urlProtocol(self, wasRedirectedTo: next as URLRequest, redirectResponse: response)
        }
        guard wasSent, let session else {
            release()
            return
        }
        releaseRedirect = release
        session.perform(after: Self.redirectGrace) { [self] in endRedirectWait() }
    }

    private func endRedirectWait() {
        releaseRedirect?()
        releaseRedirect = nil
    }

    func didReceive(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard Self.forwardedChallenges.contains(challenge.protectionSpace.authenticationMethod) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // The app's delegate decides, so certificate pinning and client certificates keep working.
        challengeHandler = completionHandler
        let forwarded = URLAuthenticationChallenge(authenticationChallenge: challenge, sender: self)
        if !sendToClient({ $0.urlProtocol(self, didReceive: forwarded) }) {
            challengeHandler = nil
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    func didCollect(_ metrics: URLSessionTaskMetrics) {
        self.metrics = metrics
        if completion != nil {
            finish()
        }
    }

    func didComplete(error: (any Error)?) {
        spooledFile.map(RequestBodyReader.remove)
        sendToClient { client in
            if let error {
                client.urlProtocol(self, didFailWithError: error)
            } else {
                client.urlProtocolDidFinishLoading(self)
            }
        }
        // A followed redirect cancels this load, which isn't a failure of the request.
        completion = (isRedirected ? nil : error, Date())
        if metrics != nil {
            finish()
        } else if let session {
            session.perform(after: Self.metricsGrace) { [self] in finish() }
        }
    }

    private func finish() {
        guard !isRecorded, let completion else { return }
        isRecorded = true
        engine?.submit(
            RawExchange(
                id: id,
                request: request,
                requestBody: requestBody,
                response: response,
                responseBody: responseBody,
                error: completion.error,
                metrics: metrics,
                startDate: startDate,
                endDate: completion.date
            )
        )
    }

    private func resolveChallenge(_ disposition: URLSession.AuthChallengeDisposition, _ credential: URLCredential?) {
        session?.perform { [self] in
            challengeHandler?(disposition, credential)
            challengeHandler = nil
        }
    }
}

extension CustomURLProtocol: URLAuthenticationChallengeSender {
    func use(_ credential: URLCredential, for challenge: URLAuthenticationChallenge) {
        resolveChallenge(.useCredential, credential)
    }

    func continueWithoutCredential(for challenge: URLAuthenticationChallenge) {
        resolveChallenge(.useCredential, nil)
    }

    func cancel(_ challenge: URLAuthenticationChallenge) {
        resolveChallenge(.cancelAuthenticationChallenge, nil)
    }

    func performDefaultHandling(for challenge: URLAuthenticationChallenge) {
        resolveChallenge(.performDefaultHandling, nil)
    }

    func rejectProtectionSpaceAndContinue(with challenge: URLAuthenticationChallenge) {
        resolveChallenge(.rejectProtectionSpace, nil)
    }
}

/// The same capture for `.ephemeral` configurations, so their cookies and cache stay private to them.
final class EphemeralURLProtocol: CustomURLProtocol, @unchecked Sendable {
    override static var sessionKind: SessionKind { .ephemeral }
}
