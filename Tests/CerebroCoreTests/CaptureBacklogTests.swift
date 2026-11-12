import Testing
@testable import CerebroCore

@Test func admitsUpToTheFrameLimit() {
    let backlog = CaptureBacklog(frameLimit: 2, byteLimit: 1_000)

    #expect(backlog.admit(bytes: 1))
    #expect(backlog.admit(bytes: 1))
    #expect(!backlog.admit(bytes: 1))
}

@Test func admitsUpToTheByteLimit() {
    let backlog = CaptureBacklog(frameLimit: 10, byteLimit: 100)

    #expect(backlog.admit(bytes: 60))
    #expect(backlog.admit(bytes: 40))
    #expect(!backlog.admit(bytes: 1))
}

@Test func finishingFreesRoom() {
    let backlog = CaptureBacklog(frameLimit: 1, byteLimit: 100)
    #expect(backlog.admit(bytes: 100))
    #expect(!backlog.admit(bytes: 100))

    backlog.finish(bytes: 100)

    #expect(backlog.admit(bytes: 100))
}

@Test func oneOversizedPayloadMayWaitAloneWhenAsked() {
    let backlog = CaptureBacklog(byteLimit: 10)

    #expect(!backlog.admit(bytes: 50))
    #expect(backlog.admit(bytes: 50, evenIfAlone: true))
    #expect(!backlog.admit(bytes: 1, evenIfAlone: true))

    backlog.finish(bytes: 50)

    #expect(backlog.admit(bytes: 1))
}

@Test func theLargestLimitDoesntOverflow() {
    let backlog = CaptureBacklog(frameLimit: 2, byteLimit: .max)

    #expect(backlog.admit(bytes: .max))
    #expect(!backlog.admit(bytes: 1))
}
