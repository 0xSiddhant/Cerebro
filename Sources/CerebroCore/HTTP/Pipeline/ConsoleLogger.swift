import Foundation

/// Prints transactions at the configured level. Everything it sees is already redacted. An event
/// stream is printed once, when it ends.
struct ConsoleLogger: Sendable {
    let level: ConsoleLevel
    var write: @Sendable (String) -> Void = { print($0) }

    func log(_ transaction: HTTPTransaction) {
        guard level != .off else { return }
        write(summary(of: transaction))
        if level == .full {
            write(details(of: transaction))
        }
    }

    private func summary(of transaction: HTTPTransaction) -> String {
        let request = transaction.request
        var parts = ["[Cerebro]", request.method, request.url?.absoluteString ?? "(no URL)", status(of: transaction)]
        if let total = transaction.timing?.total {
            parts.append("\(Int((total * 1000).rounded())) ms")
        }
        return parts.joined(separator: " ")
    }

    private func status(of transaction: HTTPTransaction) -> String {
        switch transaction.outcome {
        case .failed: return "failed: \(transaction.failure?.description ?? "no response")"
        case .cancelled: return "cancelled"
        default: return transaction.response.map { String($0.statusCode) } ?? ""
        }
    }

    private func details(of transaction: HTTPTransaction) -> String {
        let response = transaction.response
        return [
            section("Request headers", transaction.request.headers),
            body("Request body", transaction.request.body),
            section("Response headers", response?.headers ?? []),
            body("Response body", response?.body),
            events(of: transaction.eventStream),
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private func section(_ title: String, _ fields: [NamedValue]) -> String? {
        guard !fields.isEmpty else { return nil }
        return ([title + ":"] + fields.map { "  \($0.name): \($0.value)" }).joined(separator: "\n")
    }

    private func events(of stream: CapturedEventStream?) -> String? {
        guard let stream, stream.eventCount > 0 else { return nil }
        let kept = stream.events.count
        let title = kept == stream.eventCount ? "Events (\(kept)):" : "Events (newest \(kept) of \(stream.eventCount)):"
        return ([title] + stream.events.map(line)).joined(separator: "\n")
    }

    private func line(for event: CapturedSSEEvent) -> String {
        let name = event.id.map { "\(event.type) #\($0)" } ?? event.type
        switch event.data.content {
        case .complete: return "  \(name): \(BodyFormatter.raw(event.data))"
        case .truncated: return "  \(name) (truncated): \(BodyFormatter.raw(event.data))"
        case .withheld: return "  \(name): withheld, because it couldn't be redacted"
        case .notStored: return "  \(name): not stored"
        }
    }

    private func body(_ title: String, _ body: CapturedBody?) -> String? {
        guard let body else { return nil }
        switch body.content {
        case .complete:
            return "\(title):\n\(BodyFormatter.pretty(body))"
        case .truncated:
            return "\(title) (truncated, \(body.byteCount) bytes in all):\n\(BodyFormatter.raw(body))"
        case .withheld:
            return "\(title): withheld, because it couldn't be redacted"
        case .notStored:
            return "\(title): not stored"
        }
    }
}
