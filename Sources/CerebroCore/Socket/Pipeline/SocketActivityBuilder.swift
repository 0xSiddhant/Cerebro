import Foundation

/// Turns raw socket activity into a timeline item, running each payload through the HTTP pipeline.
struct SocketActivityBuilder: Sendable {
    let processor: BodyProcessor

    func item(from activity: RawSocketActivity) -> SocketTimelineItem {
        switch activity.content {
        case .event(let event):
            return .event(redacted(event), date: activity.date)
        case .frame(let frame):
            return .frame(
                SocketFrame(
                    direction: frame.direction,
                    kind: frame.kind,
                    byteCount: frame.byteCount,
                    date: activity.date,
                    payload: payload(of: frame, socket: activity.socket),
                    didFail: frame.didFail
                )
            )
        }
    }

    private func payload(of frame: RawSocketFrame, socket: SocketIdentity) -> CapturedBody? {
        guard let body = frame.body else {
            return frame.byteCount > 0 ? CapturedBody(content: .notStored, byteCount: frame.byteCount) : nil
        }
        let context = BodyContext(
            url: Self.url(fromName: socket.name),
            method: "SOCKET",
            contentType: nil,
            direction: frame.direction == .sent ? .request : .response,
            carrier: frame.kind == .binary ? .binaryFrame : .textFrame
        )
        // A text frame can't carry app compression, and its first bytes can look like a zlib header.
        return processor.process(
            body,
            context: context,
            detectsCompression: frame.kind == .binary
        )
    }

    /// A WebSocket's name is a URL, but NWConnection's is `host:port` and a bridge's can be a bare host.
    /// Neither of those parses with a host, and a rule that names a host needs one.
    private static func url(fromName name: String) -> URL? {
        if let url = URL(string: name), url.host != nil {
            return url
        }
        return URL(string: "socket://\(name)")
    }

    /// These strings can come straight from a server or an engine, so they get the same protection.
    private func redacted(_ event: SocketEvent) -> SocketEvent {
        let redactor = processor.redactor
        switch event {
        case .closed(let code, let reason?) where redactor.mentionsJSONKey(in: reason):
            return .closed(code: code, reason: Redactor.marker)
        case .failed(let description) where redactor.mentionsJSONKey(in: description):
            return .failed(Redactor.marker)
        case .stateChanged(let state) where redactor.mentionsJSONKey(in: state):
            return .stateChanged(Redactor.marker)
        default:
            return event
        }
    }
}
