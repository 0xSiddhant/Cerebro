import Foundation
import Testing
@testable import CerebroCore

/// Collects console lines from a test that can't share mutable state across the closure.
private final class LogLines: @unchecked Sendable {
    var lines: [String] = []
}

@Test func theRootsAreTheDataContainerTheBundleAndEachGroupThatResolves() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let log = LogLines()

    let roots = FileRoot.available(
        appGroupIdentifiers: ["group.present", "group.missing", "group.notAFolder"],
        containerURL: { identifier in
            switch identifier {
            case "group.present": return folder.url
            case "group.notAFolder": return folder.url.appendingPathComponent("nothing-here")
            default: return nil
            }
        },
        log: { log.lines.append($0) }
    )

    #expect(roots.map(\.kind) == [.dataContainer, .appBundle, .appGroup("group.present")])
    #expect(roots.map(\.name) == ["Data Container", "App Bundle", "group.present"])
    #expect(roots.map(\.isReadOnly) == [false, true, false])
    #expect(log.lines.count == 2)
    #expect(log.lines.allSatisfy { $0.hasPrefix("[Cerebro]") })
    #expect(log.lines[0].contains("group.missing"))
    #expect(log.lines[1].contains("group.notAFolder"))
}

@Test func noGroupsMeansNoLookupAndNoLog() {
    let log = LogLines()
    let roots = FileRoot.available(
        appGroupIdentifiers: [],
        containerURL: { _ in
            Issue.record("looked up a group")
            return nil
        },
        log: { log.lines.append($0) }
    )

    #expect(roots.count == 2)
    #expect(log.lines.isEmpty)
}

@Test func containmentFollowsLinksInFoldersButNotInTheItemsOwnName() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let root = folder.root
    let outsideFile = try folder.file("secret.txt", in: folder.outside)
    let link = try folder.link("escape", to: outsideFile)
    let folderLink = try folder.link("escape-folder", to: folder.outside)

    #expect(root.containsItem(at: folder.url.appendingPathComponent("a/b.txt")))
    #expect(root.containsItem(at: link))
    #expect(!root.containsTarget(of: link))
    #expect(!root.containsItem(at: folderLink.appendingPathComponent("secret.txt")))
    #expect(!root.containsItem(at: folder.url.appendingPathComponent("..")))
    #expect(!root.containsItem(at: folder.url.appendingPathComponent("sub/../../outside/secret.txt")))
    #expect(!root.containsTarget(of: folder.base))
    #expect(root.isRootFolder(folder.url))
}

@Test func theRelativePathIsInsideTheRoot() throws {
    let folder = try TemporaryFolder()
    defer { folder.remove() }
    let file = try folder.file("Library/Preferences/app.plist")

    #expect(folder.root.relativePath(of: file) == "Library/Preferences/app.plist")
    #expect(folder.root.relativePath(of: folder.url)?.isEmpty == true)
    #expect(folder.root.relativePath(of: folder.outside) == nil)
}

@Test func theSettingsDefaultToATabAndNoGroups() {
    let configuration = CerebroConfiguration()

    #expect(configuration.isFileBrowserEnabled)
    #expect(configuration.appGroupIdentifiers.isEmpty)
}
