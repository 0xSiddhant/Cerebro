import Foundation
import Testing
@testable import CerebroCore

@Test func formatsComeFromTheExtensionThenTheFirstBytes() {
    let none = Data()

    #expect(FileFormat(name: "Settings.plist", header: none) == .propertyList)
    #expect(FileFormat(name: "data", header: Data("bplist00rest".utf8)) == .propertyList)
    #expect(
        FileFormat(name: "info.strings", header: Data("<?xml version=\"1.0\"?>\n<!DOCTYPE plist PUBLIC".utf8))
            == .propertyList)
    #expect(FileFormat(name: "page.xml", header: Data("<?xml version=\"1.0\"?><feed>".utf8)) == .other)
    #expect(FileFormat(name: "response.JSON", header: none) == .json)
    #expect(FileFormat(name: "photo.HEIC", header: none) == .document)
    #expect(FileFormat(name: "report.pdf", header: none) == .document)
    #expect(FileFormat(name: "clip.mov", header: none) == .document)
    #expect(FileFormat(name: "notes.txt", header: none) == .document)
    #expect(FileFormat(name: "Keynote.key", header: none) == .document)
    #expect(FileFormat(name: "app.sqlite", header: Data("SQLite format 3\0".utf8)) == .other)
    #expect(FileFormat(name: "no-extension", header: none) == .other)
    #expect(FileFormat(name: "blob.bin", header: Data([0, 1, 2])) == .other)
}

@Test func aPropertyListOpensAsJSONWithDatesAndDataAsText() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let plist: [String: Any] = [
        "name": "Cerebro",
        "launches": 3,
        "isOn": true,
        "first": Date(timeIntervalSince1970: 0),
        "token": Data([1, 2, 3]),
        "list": [1.5, "two"],
    ]
    let file = folder.url.appendingPathComponent("prefs")
    try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).write(to: file)

    let body = try FileContents.body(of: file, root: folder.root, limit: 10_000)
    let json = try #require(body.data.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })

    #expect(body.isDecoded)
    #expect(body.contentType == "application/json")
    #expect(json["name"] as? String == "Cerebro")
    #expect(json["launches"] as? Int == 3)
    #expect(json["isOn"] as? Bool == true)
    #expect(json["first"] as? String == "1970-01-01T00:00:00Z")
    #expect(json["token"] as? String == "AQID")
    #expect((json["list"] as? [Any])?.count == 2)
}

/// An archive's references are values JSON can't hold, and writing one raised an exception that ended the app.
@Test func aKeyedArchiveOpensAsJSONWithoutCrashing() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let file = folder.url.appendingPathComponent("cache")
    let archive = try NSKeyedArchiver.archivedData(
        withRootObject: ["token": "abc", "count": 3] as NSDictionary, requiringSecureCoding: false)
    try archive.write(to: file)

    let body = try FileContents.body(of: file, root: folder.root, limit: 100_000)
    let json = try #require(body.data.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })

    #expect(body.isDecoded)
    #expect(json["$archiver"] as? String == "NSKeyedArchiver")
    #expect(json["$top"] is [String: Any])
}

@Test func aPropertyListOpensAsItsBytesWhenAskedOrWhenItsOverTheLimit() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let file = folder.url.appendingPathComponent("big.plist")
    let data = try PropertyListSerialization.data(
        fromPropertyList: ["key": String(repeating: "v", count: 200)], format: .binary, options: 0)
    try data.write(to: file)

    let cut = try FileContents.body(of: file, root: folder.root, limit: 50)
    let raw = try FileContents.body(of: file, root: folder.root, limit: 10_000, asRaw: true)

    #expect(cut.content == .truncated(data.prefix(50)))
    #expect(cut.byteCount == data.count)
    #expect(cut.undecoded == .truncated)
    #expect(BodyFormatter.raw(cut).hasPrefix(BodyFormatter.hex(Data("bplist00".utf8))))
    #expect(raw.content == .complete(data))
    #expect(!raw.isDecoded)
}

@Test func otherFilesAreReadUpToTheLimit() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let text = try folder.file("log", "line one\nline two")
    let emoji = try folder.file("emoji.log", "ab😀cd")
    let binary = folder.url.appendingPathComponent("blob")
    try Data([0xFF, 0xFE, 0x00, 0x01]).write(to: binary)

    let whole = try FileContents.body(of: text, root: folder.root, limit: 1_000)
    let cut = try FileContents.body(of: text, root: folder.root, limit: 4)
    // The cap falls inside the emoji, so the half character is dropped.
    let cutCharacter = try FileContents.body(of: emoji, root: folder.root, limit: 4)
    let bytes = try FileContents.body(of: binary, root: folder.root, limit: 1_000)

    #expect(whole.content == .complete(Data("line one\nline two".utf8)))
    #expect(cut.content == .truncated(Data("line".utf8)))
    #expect(cut.byteCount == 17)
    #expect(cutCharacter.content == .truncated(Data("ab".utf8)))
    #expect(BodyFormatter.raw(bytes) == "fffe0001")
}

@Test func aPropertyListThatDoesntParseOpensAsItsBytes() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let file = try folder.file("broken.plist", "not a plist")

    let body = try FileContents.body(of: file, root: folder.root, limit: 1_000)

    #expect(!body.isDecoded)
    #expect(body.content == .complete(Data("not a plist".utf8)))
}
