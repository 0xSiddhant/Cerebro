import Testing
@testable import CerebroCore

@Test func admitsUpToTheFrameLimit() {
    let backlog = SocketBacklog(frameLimit: 2, byteLimit: 1_000)

    #expect(backlog.admit(bytes: 1))
    #expect(backlog.admit(bytes: 1))
    #expect(!backlog.admit(bytes: 1))
}

@Test func admitsUpToTheByteLimit() {
    let backlog = SocketBacklog(frameLimit: 10, byteLimit: 100)

    #expect(backlog.admit(bytes: 60))
    #expect(backlog.admit(bytes: 40))
    #expect(!backlog.admit(bytes: 1))
}

@Test func finishingFreesRoom() {
    let backlog = SocketBacklog(frameLimit: 1, byteLimit: 100)
    #expect(backlog.admit(bytes: 100))
    #expect(!backlog.admit(bytes: 100))

    backlog.finish(bytes: 100)

    #expect(backlog.admit(bytes: 100))
}

@Test func theLargestLimitDoesntOverflow() {
    let backlog = SocketBacklog(frameLimit: 2, byteLimit: .max)

    #expect(backlog.admit(bytes: .max))
    #expect(!backlog.admit(bytes: 1))
}
