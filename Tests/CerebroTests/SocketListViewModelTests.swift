import Foundation
import Testing
@testable import Cerebro

private func connection(
    name: String = "wss://example.com",
    source: SocketSource = .webSocketTask,
    status: SocketStatus = .open,
    frames: Int = 0
) -> SocketConnection {
    SocketConnection(
        source: source, name: name, startDate: Date(timeIntervalSince1970: 0), status: status, frameCount: frames)
}

@MainActor
private func viewModel(_ connections: [SocketConnection]) -> SocketListViewModel {
    let model = SocketListViewModel(store: SocketStore(frameLimit: 10, payloadByteLimit: 100))
    model.show(connections)
    return model
}

@Test @MainActor func newestSocketComesFirst() {
    let model = viewModel([connection(name: "old"), connection(name: "new")])

    #expect(model.rows.map(\.name) == ["new", "old"])
}

@Test @MainActor func tagNamesTheSource() {
    let model = viewModel([
        connection(source: .webSocketTask), connection(source: .nwConnection), connection(source: .external),
    ])

    #expect(model.rows.map(\.tag) == ["EXT", "NW", "WS"])
}

@Test @MainActor func statusAndColourFollowTheSocket() {
    let model = viewModel([
        connection(status: .connecting), connection(status: .open), connection(status: .closed),
        connection(status: .failed),
    ])

    #expect(model.rows.map(\.status) == ["Failed", "Closed", "Open", "Connecting"])
    #expect(model.rows.map(\.outcome) == [.failed, .cancelled, .success, .redirection])
}

@Test @MainActor func detailCountsFrames() {
    #expect(viewModel([connection(frames: 1)]).rows.first?.detail.hasPrefix("1 frame ·") == true)
    #expect(viewModel([connection(frames: 3)]).rows.first?.detail.hasPrefix("3 frames ·") == true)
}
