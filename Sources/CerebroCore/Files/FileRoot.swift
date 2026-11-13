import Foundation

/// A place the Files tab can browse, and the boundary every file operation inside it stays within.
public struct FileRoot: Sendable, Hashable {
    /// Which place a root is.
    public enum Kind: Sendable, Hashable {
        /// The app's data container, which holds `Documents`, `Library`, `tmp` and `SystemData`.
        case dataContainer

        /// The installed app, which Cerebro never changes.
        case appBundle

        /// An App Group container, named by its identifier.
        case appGroup(String)
    }

    /// Which place this is.
    public let kind: Kind

    /// The root's folder, as the system gave it.
    public let url: URL

    /// The folder's path with every symlink resolved, which is what containment is checked against.
    private let canonicalComponents: [String]

    /// Creates a root for a folder.
    public init(kind: Kind, url: URL) {
        self.kind = kind
        self.url = url.standardizedFileURL
        canonicalComponents = Self.canonicalComponents(of: url)
    }

    /// What the Files tab calls this root.
    public var name: String {
        switch kind {
        case .dataContainer: return "Data Container"
        case .appBundle: return "App Bundle"
        case .appGroup(let identifier): return identifier
        }
    }

    /// Whether every change is refused. The app bundle is signed on a device, and on a simulator,
    /// where it could change, Cerebro refuses anyway so it behaves the same and never corrupts the app.
    public var isReadOnly: Bool {
        kind == .appBundle
    }

    /// The data container, the app bundle, and each App Group container that resolves to a folder
    /// that exists. An identifier that doesn't is left out, and the console says which.
    public static func available(appGroupIdentifiers: [String]) -> [Self] {
        available(
            appGroupIdentifiers: appGroupIdentifiers,
            containerURL: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) },
            log: { print($0) }
        )
    }

    static func available(
        appGroupIdentifiers: [String],
        containerURL: (String) -> URL?,
        log: (String) -> Void
    ) -> [Self] {
        var roots = [
            Self(kind: .dataContainer, url: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)),
            Self(kind: .appBundle, url: Bundle.main.bundleURL),
        ]
        for identifier in appGroupIdentifiers {
            // A simulator can return a folder for a group the app isn't entitled to, so it must exist.
            guard let url = containerURL(identifier), isFolder(url) else {
                log(
                    "[Cerebro] App Group \"\(identifier)\" has no container, so the Files tab leaves it out. "
                        + "Check that the app has this group in its App Groups entitlement."
                )
                continue
            }
            roots.append(Self(kind: .appGroup(identifier), url: url))
        }
        return roots
    }

    /// Whether the item at `url` is this root or inside it. Symlinks in its folders are followed, but
    /// not one in its own name, so a link can be renamed or deleted without reaching its target.
    public func containsItem(at url: URL) -> Bool {
        Self.location(of: url).starts(with: canonicalComponents)
    }

    /// Whether what `url` leads to, with every symlink followed, is this root or inside it. Anything
    /// that reads a file or a folder's contents checks this.
    public func containsTarget(of url: URL) -> Bool {
        Self.canonicalComponents(of: url).starts(with: canonicalComponents)
    }

    /// Whether `url` is this root's own folder.
    public func isRootFolder(_ url: URL) -> Bool {
        Self.canonicalComponents(of: url) == canonicalComponents
    }

    /// The item's path inside this root, such as `Library/Preferences`, or an empty string for the
    /// root itself. `nil` if it isn't inside.
    public func relativePath(of url: URL) -> String? {
        let components = isRootFolder(url) ? canonicalComponents : Self.location(of: url)
        guard components.starts(with: canonicalComponents) else { return nil }
        return components.dropFirst(canonicalComponents.count).joined(separator: "/")
    }

    /// The item's folder, resolved, followed by its own name, unresolved.
    static func location(of url: URL) -> [String] {
        let name = url.standardizedFileURL.lastPathComponent
        guard name != "/", name != ".", name != ".." else { return Self.canonicalComponents(of: url) }
        return Self.canonicalComponents(of: url.deletingLastPathComponent()) + [name]
    }

    /// A path with every symlink resolved. iOS reaches `/var` through `/private/var`, and the system
    /// returns either spelling, so the `private` prefix is dropped to compare them.
    static func canonicalComponents(of url: URL) -> [String] {
        var components = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        if components.count > 1, components[1] == "private" {
            components.remove(at: 1)
        }
        return components
    }

    static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
