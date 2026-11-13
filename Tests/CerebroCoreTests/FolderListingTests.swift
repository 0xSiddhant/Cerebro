import Foundation
import Testing
@testable import CerebroCore

@Test func aListingHasNamesKindsSizesDatesHiddenFilesAndLinks() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let target = try folder.file("data.json", "{\"a\":1}")
    try folder.file(".hidden", "secret")
    try folder.folder("Caches")
    try folder.link("shortcut", to: target)

    let entries = try FolderListing.entries(in: folder.url, root: folder.root)
    let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })

    #expect(byName.keys.sorted() == [".hidden", "Caches", "data.json", "shortcut"])
    #expect(byName["data.json"]?.kind == .file)
    #expect(byName["data.json"]?.size == 7)
    #expect(byName["data.json"]?.modified != nil)
    #expect(byName["data.json"]?.created != nil)
    #expect(byName["data.json"]?.isWritable == true)
    #expect(byName["Caches"]?.kind == .folder)
    #expect(byName["Caches"]?.size == nil)
    #expect(byName["shortcut"]?.kind == .symbolicLink)
    #expect(byName["shortcut"]?.linkTarget == target.path)
}

@Test func aFolderOutsideTheRootIsNeverListed() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let escape = try folder.link("escape", to: folder.outside)

    #expect(throws: FileOperationError.outsideRoot) {
        try FolderListing.entries(in: escape, root: folder.root)
    }
    #expect(throws: FileOperationError.outsideRoot) {
        try FolderListing.entries(in: folder.url.appendingPathComponent(".."), root: folder.root)
    }
}

@Test func eachSortOrderPutsFoldersFirst() {
    let base = URL(fileURLWithPath: "/root")
    func entry(_ name: String, _ kind: FileEntry.Kind, size: Int64? = nil, day: Double) -> FileEntry {
        FileEntry(
            url: base.appendingPathComponent(name), kind: kind, size: size,
            modified: Date(timeIntervalSince1970: day * 86_400))
    }
    let entries = [
        entry("b.txt", .file, size: 10, day: 3),
        entry("Zeta", .folder, day: 1),
        entry("a10.txt", .file, size: 300, day: 1),
        entry("Alpha", .folder, day: 4),
        entry("a2.txt", .file, size: 20, day: 2),
    ]

    #expect(FileSortOrder.name.sorted(entries).map(\.name) == ["Alpha", "Zeta", "a2.txt", "a10.txt", "b.txt"])
    #expect(FileSortOrder.date.sorted(entries).map(\.name) == ["Alpha", "Zeta", "b.txt", "a2.txt", "a10.txt"])
    #expect(FileSortOrder.size.sorted(entries).map(\.name) == ["Alpha", "Zeta", "a10.txt", "a2.txt", "b.txt"])
}

@Test func aFolderIsMeasuredThroughItsSubfoldersWithoutFollowingLinks() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    try folder.file("a.txt", "12345")
    try folder.file("sub/b.txt", "123")
    try folder.file("big.bin", String(repeating: "x", count: 1_000), in: folder.outside)
    try folder.link("sub/escape", to: folder.outside)

    let measurement = try FolderMeasurement.measure(folder.url, root: folder.root)

    // a.txt, sub, sub/b.txt and sub/escape, but nothing behind the link.
    #expect(measurement == FolderMeasurement(byteCount: 8, itemCount: 4, isPartial: false))
}

@Test func measuringStopsAtTheItemLimit() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    for index in 0..<30 {
        try folder.file("file-\(index)")
    }

    let measurement = try FolderMeasurement.measure(folder.url, root: folder.root, itemLimit: 20)

    #expect(measurement.itemCount == 20)
    #expect(measurement.isPartial)
    #expect(FolderMeasurement.itemLimit == 20_000)
}

@Test func measuringStopsWhenCancelled() async throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    try folder.file("a.txt")
    let root = folder.root
    let url = folder.url

    let task = Task.detached {
        withUnsafeCurrentTask { $0?.cancel() }
        return try FolderMeasurement.measure(url, root: root)
    }

    await #expect(throws: CancellationError.self) { try await task.value }
}

@Test func searchMatchesNamesInTheFolderAndItsSubfolders() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    try folder.file("Report.json")
    try folder.file("deep/er/report-old.json")
    try folder.file("notes.txt")
    try folder.file("report-outside.json", in: folder.outside)
    try folder.link("escape", to: folder.outside)

    let result = try FileSearch.subfolders(of: folder.url, root: folder.root, matching: "report")

    #expect(result.entries.map(\.name).sorted() == ["Report.json", "report-old.json"])
    #expect(result.stop == nil)
    #expect(FileSearch.matches("Café.txt", query: "cafe"))
    #expect(FileSearch.matches("anything", query: ""))
    #expect(!FileSearch.matches("notes.txt", query: "report"))
}

@Test func searchStopsAtEachLimitAndSaysWhich() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    for index in 0..<10 {
        try folder.file("match-\(index)")
        try folder.file("other-\(index)")
    }

    let byResults = try FileSearch.subfolders(of: folder.url, root: folder.root, matching: "match", resultLimit: 3)
    let byVisits = try FileSearch.subfolders(of: folder.url, root: folder.root, matching: "match", visitLimit: 5)

    #expect(byResults.entries.count == 3)
    #expect(byResults.stop == .resultLimit)
    #expect(byVisits.entries.count <= 5)
    #expect(byVisits.stop == .visitLimit)
    #expect(FileSearch.visitLimit == 50_000)
    #expect(FileSearch.resultLimit == 500)
}

@Test func searchStopsWhenCancelled() async throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    try folder.file("a.txt")
    let root = folder.root
    let url = folder.url

    let task = Task.detached {
        withUnsafeCurrentTask { $0?.cancel() }
        return try FileSearch.subfolders(of: url, root: root, matching: "a")
    }

    await #expect(throws: CancellationError.self) { try await task.value }
}
