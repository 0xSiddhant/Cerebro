import Foundation

/// Takes over a request, runs it through Cerebro's own session and records what happened. The app
/// always gets each callback first, and the record is handed off afterwards.
///
/// Safety for `@unchecked Sendable`: `engine` never changes, and the mutable state below is only
/// touched on the owning `CaptureSession`'s serial queue. The system calls `startLoading` and
/// `stopLoading` on other threads, so both hop onto that queue first.
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
    private static let metricsGrace: DispatchTimeInterval = .milliseconds(250)

    class var sessionKind: SessionKind { .standard }

    private let engine: HTTPCaptureEngine?
    private var runningTask: URLSessionTask?
    private var isStopped = false
    private var isRedirected = false
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
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
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
        session?.perform { [self] in
            isStopped = true
            challengeHandler?(.cancelAuthenticationChallenge, nil)
            challengeHandler = nil
            runningTask?.cancel()
        }
    }

    private func begin(with body: RequestBodyReader.Output?) {
        if let body {
            requestBody = body.captured
            spooledFile = body.spooledFile
        }
        if let error = body?.error {
            client?.urlProtocol(self, didFailWithError: error)
            completion = (error, Date())
            finish()
            return
        }
        guard !isStopped, let session,
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
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    }

    func didReceive(_ data: Data) {
        client?.urlProtocol(self, didLoad: data)
        responseBody?.append(data)
    }

    /// Hands the decision to the app's session. If it follows the redirect, it stops this load and starts
    /// a new one, and if it refuses, the 3xx that keeps arriving here is what it delivers.
    func wasRedirected(to newRequest: URLRequest, by response: HTTPURLResponse) {
        self.response = response
        isRedirected = true
        guard let next = (newRequest as NSURLRequest).mutableCopy() as? NSMutableURLRequest else { return }
        URLProtocol.removeProperty(forKey: Self.handledKey, in: next)
        client?.urlProtocol(self, wasRedirectedTo: next as URLRequest, redirectResponse: response)
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
        client?.urlProtocol(self, didReceive: forwarded)
    }

    func didCollect(_ metrics: URLSessionTaskMetrics) {
        self.metrics = metrics
        if completion != nil {
            finish()
        }
    }

    func didComplete(error: (any Error)?) {
        spooledFile.map(RequestBodyReader.remove)
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
        // A followed redirect cancels this load, which isn't a failure of the request.
        completion = (isRedirected ? nil : error, Date())
        if metrics != nil {
            finish()
        } else if let session {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.metricsGrace) { [self] in
                session.perform { [self] in finish() }
            }
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
