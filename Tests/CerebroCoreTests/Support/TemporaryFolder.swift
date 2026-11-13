import Foundation
@testable import CerebroCore

/// A fresh folder for one test, used as a writable root, with a sibling outside it for escape attempts.
/// Call `remove()` at the end.
struct TemporaryFolder {
    let base: URL
    let url: URL
    let outside: URL

    init() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("files-\(UUID().uuidString)")
        url = base.appendingPathComponent("root", isDirectory: true)
        outside = base.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    }

    var root: FileRoot {
        FileRoot(kind: .dataContainer, url: url)
    }

    var readOnlyRoot: FileRoot {
        FileRoot(kind: .appBundle, url: url)
    }

    var operations: FileOperations {
        FileOperations(root: root)
    }

    @discardableResult
    func file(_ path: String, _ text: String = "x", in folder: URL? = nil) throws -> URL {
        let file = (folder ?? url).appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        return file
    }

    @discardableResult
    func folder(_ path: String) throws -> URL {
        let folder = url.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @discardableResult
    func link(_ path: String, to destination: URL) throws -> URL {
        let link = url.appendingPathComponent(path)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: destination)
        return link
    }

    func names(in folder: URL? = nil) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: (folder ?? url).path).sorted()
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func remove() {
        try? FileManager.default.removeItem(at: base)
    }
}
