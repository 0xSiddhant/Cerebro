import Foundation
import Testing
@testable import CerebroCore

private func identity(_ name: String = "socket") -> SocketIdentity {
    SocketIdentity(id: UUID(), source: .external, name: name)
}

private let start = Date(timeIntervalSince1970: 0)

private func frame(
    _ size: Int,
    direction: SocketDirection = .sent,
    at offset: TimeInterval = 0,
    didFail: Bool = false
) -> SocketTimelineItem {
    .frame(
        SocketFrame(
            direction: direction,
            kind: .binary,
            byteCount: size,
            date: start.addingTimeInterval(offset),
            payload: CapturedBody(content: .complete(Data(count: size)), byteCount: size),
            didFail: didFail
        )
    )
}

private func event(_ event: SocketEvent) -> SocketTimelineItem {
    .event(event, date: start)
}

private func store(frames: Int = 1_000, connections: Int = 100, bytes: Int = 1_000_000) -> SocketStore {
    SocketStore(frameLimit: frames, connectionLimit: connections, payloadByteLimit: bytes)
}

@Test func frameOverTheLimitEvictsTheOldest() async throws {
    let store = store()
    let socket = identity()

    for index in 0...1_000 {
        await store.record(frame(1, at: TimeInterval(index)), on: socket)
    }

    let connection = try #require(await store.connections.first)
    #expect(connection.timeline.count == 1_000)
    #expect(connection.timeline.first?.date == start.addingTimeInterval(1))
    #expect(connection.timeline.last?.date == start.addingTimeInterval(1_000))
    #expect(connection.frameCount == 1_001)
}

@Test func totalsCountEachDirectionAndSurviveEviction() async throws {
    let store = store(frames: 1)
    let socket = identity()

    await store.record(frame(10, direction: .sent), on: socket)
    await store.record(frame(20, direction: .received), on: socket)

    let connection = try #require(await store.connections.first)
    #expect(connection.bytesSent == 10)
    #expect(connection.bytesReceived == 20)
    #expect(connection.timeline.count == 1)
}

@Test func eventsMoveTheStatus() async throws {
    let store = store()
    let socket = identity()
    await store.record(event(.stateChanged("Preparing")), on: socket)
    #expect(await store.connections.first?.status == .connecting)

    await store.record(event(.opened), on: socket)
    #expect(await store.connections.first?.status == .open)

    await store.record(event(.closed(code: 1000, reason: "done")), on: socket)
    #expect(await store.connections.first?.status == .closed)

    let other = identity()
    await store.record(event(.failed("broke")), on: other)
    #expect(await store.connections.last?.status == .failed)
}

@Test func aFrameBeforeAnyOpenEventMeansTheSocketIsOpen() async {
    let store = store()

    await store.record(frame(1), on: identity())

    #expect(await store.connections.first?.status == .open)
}

@Test func payloadByteLimitTrimsTheSocketIdleLongestFirst() async throws {
    let store = store(bytes: 100)
    let old = identity("old")
    let new = identity("new")
    await store.record(frame(60), on: old)
    await store.record(frame(30), on: new)

    await store.record(frame(30), on: new)

    let connections = await store.connections
    #expect(connections.map(\.name) == ["old", "new"])
    #expect(connections[0].timeline.isEmpty)
    #expect(connections[1].timeline.count == 2)
}

@Test func anOlderSocketStillInUseKeepsItsHistory() async {
    let store = store(bytes: 100)
    let live = identity("live")
    let idle = identity("idle")
    await store.record(frame(40), on: live)
    await store.record(frame(40), on: idle)
    await store.record(frame(1), on: live)

    await store.record(frame(40), on: live)

    let connections = await store.connections
    #expect(connections.map(\.name) == ["live", "idle"])
    #expect(connections[0].timeline.count == 3)
    #expect(connections[1].timeline.isEmpty)
}

@Test func connectionLimitKeepsAnOlderSocketStillInUse() async {
    let store = store(connections: 2)
    let live = identity("live")
    await store.record(frame(1), on: live)
    await store.record(frame(1), on: identity("idle"))
    await store.record(frame(1), on: live)

    await store.record(frame(1), on: identity("new"))

    #expect(await store.connections.map(\.name) == ["live", "new"])
}

@Test func aFailedSocketStaysFailedWhenTheAppThenCancels() async {
    let store = store()
    let socket = identity()

    await store.record(event(.failed("reset")), on: socket)
    await store.record(event(.closed(code: nil, reason: nil)), on: socket)

    #expect(await store.connections.first?.status == .failed)
}

@Test func aClosedSocketStaysClosedWhenALateFailureArrives() async {
    let store = store()
    let socket = identity()

    await store.record(event(.closed(code: 1000, reason: nil)), on: socket)
    await store.record(event(.failed("cancelled")), on: socket)

    #expect(await store.connections.first?.status == .closed)
}

@Test func aSocketThatReopensIsOpenAgain() async {
    let store = store()
    let socket = identity()
    await store.record(event(.closed(code: 1000, reason: nil)), on: socket)

    await store.record(event(.opened), on: socket)

    #expect(await store.connections.first?.status == .open)
}

@Test func aFailedSendIsAFrameButNotBytesSentOrProofOfOpening() async throws {
    let store = store()

    await store.record(frame(10, didFail: true), on: identity())

    let connection = try #require(await store.connections.first)
    #expect(connection.frameCount == 1)
    #expect(connection.bytesSent == 0)
    #expect(connection.status == .connecting)
}

@Test func payloadByteLimitTrimsASingleSocketFromItsOldestFrame() async throws {
    let store = store(bytes: 100)
    let socket = identity()

    for index in 0..<4 {
        await store.record(frame(40, at: TimeInterval(index)), on: socket)
    }

    let connection = try #require(await store.connections.first)
    #expect(connection.timeline.count == 2)
    #expect(connection.timeline.first?.date == start.addingTimeInterval(2))
}

@Test func evictionFreesItsBytes() async throws {
    let store = store(frames: 2, bytes: 100)
    let socket = identity()

    for index in 0..<10 {
        await store.record(frame(50, at: TimeInterval(index)), on: socket)
    }

    let connection = try #require(await store.connections.first)
    #expect(connection.timeline.count == 2)
}

@Test func connectionLimitDropsTheSocketIdleLongestAndItsBytes() async {
    let store = store(connections: 2, bytes: 100)
    let first = identity("first")

    await store.record(frame(90), on: first)
    await store.record(frame(1), on: identity("second"))
    await store.record(frame(90), on: identity("third"))

    let connections = await store.connections
    #expect(connections.map(\.name) == ["second", "third"])
    #expect(connections.allSatisfy { !$0.timeline.isEmpty })
}

@Test func aBurstOfFramesArrivesAsABatch() async throws {
    let store = SocketStore(frameLimit: 1_000, payloadByteLimit: 1_000_000, updateInterval: .milliseconds(200))
    let socket = identity()
    let counter = BatchCounter()
    let reader = Task {
        for await connections in await store.updates() {
            await counter.add(connections.first?.frameCount ?? 0)
        }
    }

    for _ in 0..<200 {
        await store.record(frame(1), on: socket)
    }
    try await Task.sleep(for: .milliseconds(600))
    reader.cancel()

    let batches = await counter.values
    #expect(batches.count <= 3)
    #expect(batches.last == 200)
}

private actor BatchCounter {
    private(set) var values: [Int] = []

    func add(_ value: Int) {
        values.append(value)
    }
}

@Test func payloadByteLimitCountsAFramesOriginalBytes() async throws {
    let store = store(bytes: 100)
    let socket = identity()
    let decoded = SocketTimelineItem.frame(
        SocketFrame(
            direction: .received,
            kind: .binary,
            byteCount: 40,
            date: start,
            payload: CapturedBody(
                content: .complete(Data(count: 40)),
                byteCount: 40,
                isDecoded: true,
                rawData: Data(count: 40)
            ),
            didFail: false
        )
    )

    await store.record(decoded, on: socket)
    await store.record(decoded, on: socket)

    let connection = try #require(await store.connections.first)
    #expect(connection.timeline.count == 1)
}
