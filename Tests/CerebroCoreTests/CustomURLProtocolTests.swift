import Foundation
import Testing
@testable import CerebroCore

extension CaptureTests {
    @Suite struct ClientContract {
        private let client = RecordingClient()
        private let url = URL(string: "https://example.com/start")

        private func makeProtocol() throws -> CustomURLProtocol {
            CustomURLProtocol(request: URLRequest(url: try #require(url)), cachedResponse: nil, client: client)
        }

        private func sendEveryCallback(to loader: CustomURLProtocol) throws {
            let url = try #require(url)
            let response = try #require(
                HTTPURLResponse(url: url, statusCode: 302, httpVersion: nil, headerFields: nil)
            )
            loader.wasRedirected(to: URLRequest(url: url), by: response) {}
            loader.didReceive(response as URLResponse)
            loader.didReceive(Data("body".utf8))
            loader.didComplete(error: nil)
        }

        @Test func callbacksReachTheClientWhileLoading() throws {
            try sendEveryCallback(to: try makeProtocol())

            #expect(client.calls == ["redirect", "response", "data", "finish"])
        }

        @Test func nothingReachesTheClientAfterStopLoading() throws {
            let loader = try makeProtocol()

            loader.stopLoading()
            try sendEveryCallback(to: loader)

            #expect(client.calls.isEmpty)
        }

        @Test func failureAfterStopLoadingStaysAwayFromTheClient() throws {
            let loader = try makeProtocol()

            loader.stopLoading()
            loader.didComplete(error: URLError(.cancelled))

            #expect(client.calls.isEmpty)
        }

        @Test func challengeAfterStopLoadingIsCancelledInsteadOfHanging() throws {
            let loader = try makeProtocol()
            let space = URLProtectionSpace(
                host: "example.com",
                port: 443,
                protocol: NSURLProtectionSpaceHTTPS,
                realm: nil,
                authenticationMethod: NSURLAuthenticationMethodClientCertificate
            )
            let challenge = URLAuthenticationChallenge(
                protectionSpace: space,
                proposedCredential: nil,
                previousFailureCount: 0,
                failureResponse: nil,
                error: nil,
                sender: loader
            )
            var disposition: URLSession.AuthChallengeDisposition?

            loader.stopLoading()
            loader.didReceive(challenge) { answer, _ in disposition = answer }

            #expect(disposition == .cancelAuthenticationChallenge)
            #expect(client.calls.isEmpty)
        }
    }
}

/// Safety for `@unchecked Sendable`: each test uses it from one thread.
private final class RecordingClient: NSObject, URLProtocolClient, @unchecked Sendable {
    private(set) var calls: [String] = []

    func urlProtocol(_ protocol: URLProtocol, wasRedirectedTo request: URLRequest, redirectResponse: URLResponse) {
        calls.append("redirect")
    }

    func urlProtocol(_ protocol: URLProtocol, cachedResponseIsValid cachedResponse: CachedURLResponse) {}

    func urlProtocol(
        _ protocol: URLProtocol,
        didReceive response: URLResponse,
        cacheStoragePolicy policy: URLCache.StoragePolicy
    ) {
        calls.append("response")
    }

    func urlProtocol(_ protocol: URLProtocol, didLoad data: Data) {
        calls.append("data")
    }

    func urlProtocolDidFinishLoading(_ protocol: URLProtocol) {
        calls.append("finish")
    }

    func urlProtocol(_ protocol: URLProtocol, didFailWithError error: any Error) {
        calls.append("failure")
    }

    func urlProtocol(_ protocol: URLProtocol, didReceive challenge: URLAuthenticationChallenge) {
        calls.append("challenge")
    }

    func urlProtocol(_ protocol: URLProtocol, didCancel challenge: URLAuthenticationChallenge) {}
}
