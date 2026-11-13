import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// Turns the items chosen for sharing into files the share sheet can send.
enum FileSharePreparation {
    /// Each file as it is, and each folder zipped by the system. A link is shared as what it leads to,
    /// and only if that's inside the root. It blocks, so call it off the main thread.
    static func prepare(_ entries: [FileEntry], root: FileRoot) throws -> PreparedShare {
        guard entries.allSatisfy({ root.containsTarget(of: $0.url) }) else { throw FileOperationError.outsideRoot }
        let temporaryFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var zipsFolders = false
        do {
            let files = try entries.map { entry in
                let item = entry.kind == .symbolicLink ? entry.url.resolvingSymlinksInPath() : entry.url
                guard (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return item }
                zipsFolders = true
                return try zip(item, into: temporaryFolder)
            }
            return PreparedShare(files: files, temporaryFolder: zipsFolders ? temporaryFolder : nil)
        } catch {
            try? FileManager.default.removeItem(at: temporaryFolder)
            throw error
        }
    }

    /// Zips a folder with the system's own archiver. Each zip gets a folder of its own, so two folders
    /// with the same name can be shared together.
    private static func zip(_ folder: URL, into temporaryFolder: URL) throws -> URL {
        let destination = temporaryFolder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let zipped = destination.appendingPathComponent(folder.lastPathComponent + ".zip")
        var coordinationError: NSError?
        var copyError: (any Error)?
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zip in
            // The system removes its zip when this returns, so it's copied out first.
            do {
                try FileManager.default.copyItem(at: zip, to: zipped)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError {
            throw error
        }
        return zipped
    }
}
