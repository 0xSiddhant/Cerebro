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

    /// Waits up to a second for at least `expected` reports.
    func reaches(_ expected: Int) async -> Bool {
        for _ in 0..<100 where count < expected {
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

@Test func theWatcherReportsABurstOnce() async throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let (reports, watching) = await watch(folder.url, batchingFor: .milliseconds(300))
    defer { watching.cancel() }

    for index in 0..<50 {
        try folder.file("burst-\(index)")
    }
    try await Task.sleep(for: .milliseconds(600))

    #expect(reports.count == 1)
}

@Test func theWatcherEndsForAFolderThatDoesntExist() async {
    var reports = 0
    for await _ in FolderWatcher.changes(in: URL(fileURLWithPath: "/no/such/folder-\(UUID().uuidString)")) {
        reports += 1
    }

    #expect(reports == 0)
}
