import Foundation
import Testing
@testable import CerebroCore

/// Counts a watcher's reports. Safety for `@unchecked Sendable`: every access holds the lock.
private final class ReportCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int {
        lock.withLock { value }
    }

    func add() {
        lock.withLock { value += 1 }
    }

    /// Waits for at least `expected` reports, up to `limit`.
    func reaches(_ expected: Int, within limit: Duration = .seconds(1)) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while count < expected, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return count >= expected
    }
}

/// Starts watching at once, so nothing that happens after this call is missed.
private func watch(
    _ folder: URL,
    batchingFor interval: DispatchTimeInterval
) async -> (ReportCounter, Task<Void, Never>) {
    let changes = FolderWatcher.changes(in: folder, batchingFor: interval)
    let counter = ReportCounter()
    let task = Task {
        for await _ in changes {
            counter.add()
        }
    }
    // The source registers with the kernel on its own queue.
    try? await Task.sleep(for: .milliseconds(50))
    return (counter, task)
}

@Test func theWatcherReportsAnAddedRenamedAndRemovedEntry() async throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let (reports, watching) = await watch(folder.url, batchingFor: .milliseconds(20))
    defer { watching.cancel() }

    let file = try folder.file("added.txt")
    #expect(await reports.reaches(1))

    let renamed = folder.url.appendingPathComponent("renamed.txt")
    try FileManager.default.moveItem(at: file, to: renamed)
    #expect(await reports.reaches(2))

    try FileManager.default.removeItem(at: renamed)
    #expect(await reports.reaches(3))
}

@Test func theWatcherBatchesABurst() async throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let (reports, watching) = await watch(folder.url, batchingFor: .seconds(1))
    defer { watching.cancel() }

    for index in 0..<50 {
        try folder.file("burst-\(index)")
    }
    #expect(await reports.reaches(1, within: .seconds(3)))
    // Nothing else is written, so a second report could only be the rest of the burst.
    try await Task.sleep(for: .seconds(1.2))

    // 50 changes, but a slow runner can split them across two windows.
    #expect((1...2).contains(reports.count))
}

@Test func theWatcherEndsForAFolderThatDoesntExist() async {
    var reports = 0
    for await _ in FolderWatcher.changes(in: URL(fileURLWithPath: "/no/such/folder-\(UUID().uuidString)")) {
        reports += 1
    }

    #expect(reports == 0)
}
