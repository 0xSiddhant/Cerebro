import Foundation

/// Turns raw socket activity into a timeline item, running each payload through the HTTP pipeline.
struct SocketActivityBuilder: Sendable {
    let processor: BodyProcessor

    func item(from activity: RawSocketActivity) -> SocketTimelineItem {
        switch activity.content {
        case .event(let event):
            return .event(event, date: activity.date)
        case .frame(let direction, let payload):
            return .frame(frame(direction, payload, socket: activity.socket, date: activity.date))
        }
    }

    private func frame(
        _ direction: SocketDirection,
        _ payload: SocketPayload,
        socket: SocketIdentity,
        date: Date
    ) -> SocketFrame {
        let data: Data
        let kind: SocketFrame.Kind
        switch payload {
        case .text(let text):
            data = Data(text.utf8)
            kind = .text
        case .binary(let bytes):
            data = bytes
            kind = .binary
        }
        let context = BodyContext(
            url: URL(string: socket.name),
            method: "SOCKET",
            contentType: nil,
            direction: direction == .sent ? .request : .response
        )
        return SocketFrame(
            direction: direction,
            kind: kind,
            byteCount: data.count,
            date: date,
            payload: processor.process(RawBody(data: data, limit: processor.limit), context: context)
        )
    }
}
