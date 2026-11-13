import Foundation
import Testing
@testable import CerebroCore

@Test func renameDuplicateAndNewFolderChangeTheDisk() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let file = try folder.file("a.txt", "hello")

    let renamed = try folder.operations.rename(file, to: "b.txt")
    let copy = try folder.operations.duplicate(renamed)
    let created = try folder.operations.createFolder(named: "New", in: folder.url)

    #expect(try folder.names() == ["New", "b 2.txt", "b.txt"])
    #expect(copy.lastPathComponent == "b 2.txt")
    #expect(try String(contentsOf: copy, encoding: .utf8) == "hello")
    #expect(created.lastPathComponent == "New")
}

@Test func aRenameThatOnlyChangesCaseWorks() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let file = try folder.file("readme.txt")

    try folder.operations.rename(file, to: "README.txt")

    #expect(try folder.names() == ["README.txt"])
}

@Test func copyAndMoveGoIntoAnotherFolder() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let first = try folder.file("one.txt")
    let second = try folder.file("two/inner.txt")
    let destination = try folder.folder("dest")

    try folder.operations.copy([first], into: destination)
    try folder.operations.move([first, second.deletingLastPathComponent()], into: destination)

    #expect(try folder.names() == ["dest"])
    #expect(try folder.names(in: destination) == ["one 2.txt", "one.txt", "two"])
    #expect(folder.exists(destination.appendingPathComponent("two/inner.txt")))
}

@Test func movingIntoTheSameFolderChangesNothing() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let file = try folder.file("same.txt")

    let moved = try folder.operations.move([file], into: folder.url)

    #expect(moved == [file])
    #expect(try folder.names() == ["same.txt"])
}

@Test func deleteAndDeleteContents() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let file = try folder.file("gone.txt")
    let caches = try folder.folder("Caches")
    try folder.file("Caches/a")
    try folder.file("Caches/sub/b")

    try folder.operations.delete([file])
    try folder.operations.deleteContents(of: caches)

    #expect(try folder.names() == ["Caches"])
    #expect(try folder.names(in: caches).isEmpty)
}

@Test func anItemInsideAnotherSelectedOneGoesWithIt() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let logs = try folder.folder("Logs")
    let today = try folder.file("Logs/today.log")
    let copies = try folder.folder("Copies")
    let moved = try folder.folder("Moved")

    let copied = try folder.operations.copy([logs, today], into: copies)
    try folder.operations.move([today, logs], into: moved)
    try folder.operations.delete([moved.appendingPathComponent("Logs"), moved.appendingPathComponent("Logs/today.log")])

    #expect(copied.map(\.lastPathComponent) == ["Logs"])
    #expect(try folder.names(in: copies) == ["Logs"])
    #expect(try folder.names(in: copies.appendingPathComponent("Logs")) == ["today.log"])
    #expect(try folder.names(in: moved).isEmpty)
    #expect(try folder.names() == ["Copies", "Moved"])
}

@Test func deletingALinkLeavesItsTarget() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let target = try folder.file("kept.txt", in: folder.outside)
    let link = try folder.link("link", to: target)

    try folder.operations.delete([link])

    #expect(!folder.exists(link))
    #expect(folder.exists(target))
}

@Test func importMovesAFileInAndNumbersATakenName() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    try folder.file("seed.json")
    let picked = try folder.file("seed.json", "{}", in: folder.outside)

    let imported = try folder.operations.importItem(at: picked, into: folder.url)

    #expect(imported.lastPathComponent == "seed 2.json")
    #expect(try String(contentsOf: imported, encoding: .utf8) == "{}")
}

@Test func takenNamesAreNumberedInOrderOrRefused() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let file = try folder.file("name.ext")
    let other = try folder.file("other.ext")
    try folder.folder("Folder")

    let second = try folder.operations.duplicate(file)
    let third = try folder.operations.duplicate(file)
    let numberedFolder = try folder.operations.freeLocation(for: "Folder", in: folder.url)

    #expect(second.lastPathComponent == "name 2.ext")
    #expect(third.lastPathComponent == "name 3.ext")
    #expect(numberedFolder.lastPathComponent == "Folder 2")
    #expect(throws: FileOperationError.nameTaken("name.ext")) { try folder.operations.rename(other, to: "name.ext") }
    #expect(throws: FileOperationError.nameTaken("Folder")) {
        try folder.operations.createFolder(named: "Folder", in: folder.url)
    }
    #expect(try String(contentsOf: file, encoding: .utf8) == "x")
}

@Test func badNamesAreRefused() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let file = try folder.file("a.txt")

    for name in ["", ".", "..", "a/b", "../escape"] {
        #expect(throws: FileOperationError.invalidName) { try folder.operations.rename(file, to: name) }
        #expect(throws: FileOperationError.invalidName) {
            try folder.operations.createFolder(named: name, in: folder.url)
        }
    }
    #expect(try folder.names() == ["a.txt"])
}

@Test func nothingOutsideTheRootCanBeReachedOrChanged() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let secret = try folder.file("secret.txt", "keep", in: folder.outside)
    let fileLink = try folder.link("file-link", to: secret)
    let folderLink = try folder.link("folder-link", to: folder.outside)
    let inside = try folder.file("inside.txt")
    let operations = folder.operations

    #expect(throws: FileOperationError.outsideRoot) { try operations.delete([secret]) }
    #expect(throws: FileOperationError.outsideRoot) { try operations.rename(secret, to: "moved.txt") }
    #expect(throws: FileOperationError.outsideRoot) { try operations.move([inside], into: folder.outside) }
    #expect(throws: FileOperationError.outsideRoot) { try operations.copy([inside], into: folderLink) }
    #expect(throws: FileOperationError.outsideRoot) { try operations.deleteContents(of: folderLink) }
    #expect(throws: FileOperationError.outsideRoot) {
        try operations.delete([folderLink.appendingPathComponent("secret.txt")])
    }
    #expect(throws: FileOperationError.outsideRoot) {
        try operations.createFolder(named: "x", in: folder.url.appendingPathComponent(".."))
    }
    #expect(throws: FileOperationError.outsideRoot) {
        try FileContents.body(of: fileLink, root: folder.root, limit: 100)
    }
    #expect(throws: FileOperationError.outsideRoot) {
        try FileDetails.read(secret, root: folder.root)
    }
    #expect(try String(contentsOf: secret, encoding: .utf8) == "keep")
    #expect(try folder.names(in: folder.outside) == ["secret.txt"])
    #expect(try folder.names() == ["file-link", "folder-link", "inside.txt"])
}

@Test func theRootsOwnFolderAndAFolderIntoItselfAreRefused() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let parent = try folder.folder("parent")
    let child = try folder.folder("parent/child")
    let operations = folder.operations

    #expect(throws: FileOperationError.rootFolder) { try operations.delete([folder.url]) }
    #expect(throws: FileOperationError.rootFolder) { try operations.deleteContents(of: folder.url) }
    #expect(throws: FileOperationError.rootFolder) { try operations.rename(folder.url, to: "other") }
    #expect(throws: FileOperationError.intoItself) { try operations.move([parent], into: child) }
    #expect(throws: FileOperationError.intoItself) { try operations.copy([parent], into: parent) }
    #expect(folder.exists(child))
}

@Test func aReadOnlyRootRefusesEveryChange() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let file = try folder.file("app.txt")
    let sub = try folder.folder("sub")
    let picked = try folder.file("picked.txt", in: folder.outside)
    let operations = FileOperations(root: folder.readOnlyRoot)

    #expect(throws: FileOperationError.readOnly) { try operations.rename(file, to: "b.txt") }
    #expect(throws: FileOperationError.readOnly) { try operations.duplicate(file) }
    #expect(throws: FileOperationError.readOnly) { try operations.copy([file], into: sub) }
    #expect(throws: FileOperationError.readOnly) { try operations.move([file], into: sub) }
    #expect(throws: FileOperationError.readOnly) { try operations.delete([file]) }
    #expect(throws: FileOperationError.readOnly) { try operations.deleteContents(of: sub) }
    #expect(throws: FileOperationError.readOnly) { try operations.createFolder(named: "new", in: folder.url) }
    #expect(throws: FileOperationError.readOnly) { try operations.importItem(at: picked, into: folder.url) }
    #expect(try folder.names() == ["app.txt", "sub"])
    #expect(try folder.names(in: sub).isEmpty)
}

@Test func aFailedOperationLeavesTheFilesAsTheyWere() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let file = try folder.file("a.txt")
    let missing = folder.url.appendingPathComponent("missing.txt")

    #expect(throws: (any Error).self) { try folder.operations.rename(missing, to: "b.txt") }
    #expect(throws: (any Error).self) { try folder.operations.duplicate(missing) }
    #expect(throws: FileOperationError.outsideRoot) {
        try folder.operations.move([file, folder.outside], into: folder.url)
    }

    #expect(try folder.names() == ["a.txt"])
}
