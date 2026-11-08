import Cerebro
import Foundation
import Network

/// Sends one request over a raw TLS connection and reads the first bytes back.
///
/// All of its state is touched on `queue`, which is where the connection delivers its callbacks.
final class NWConnectionExchange: @unchecked Sendable {
    private let queue = DispatchQueue(label: "CerebroExample.NWConnectionExchange")
    private let connection = MonitoredNWConnection(host: "example.com", port: .https, using: .tls)
    private var continuation: CheckedContinuation<String, Error>?

    func run() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                self.connection.stateUpdateHandler = { self.handle($0) }
                self.connection.start(queue: self.queue)
            }
        }
    }

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            sendRequest()
        case .failed(let error), .waiting(let error):
            finish(.failure(error))
        default:
            break
        }
    }

    private func sendRequest() {
        let request = Data("HEAD / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n".utf8)

        connection.send(
            content: request,
            completion: .contentProcessed { error in
                if let error {
                    self.finish(.failure(error))
                } else {
                    self.receiveResponse()
                }
            })
    }

    private func receiveResponse() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, error in
            if let error {
                self.finish(.failure(error))
            } else {
                self.finish(.success("Received \(data?.count ?? 0) bytes"))
            }
        }
    }

    private func finish(_ result: Result<String, Error>) {
        continuation?.resume(with: result)
        continuation = nil
        connection.cancel()
    }
}
