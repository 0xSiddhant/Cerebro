import Foundation

/// How much a folder holds, counted through every subfolder. Links are counted but never followed.
public struct FolderMeasurement: Sendable, Equatable {
    /// Items counted before the count stops, so a huge folder can't keep the device busy.
    public static let itemLimit = 20_000

    /// The bytes in the files counted.
    public let byteCount: Int64

    /// The files, folders and links counted.
    public let itemCount: Int

    /// Whether counting stopped at the limit, so the folder holds more than this says.
    public let isPartial: Bool

    /// Measures a folder. It blocks, so call it from a task off the main thread, and cancelling that
    /// task stops it with `CancellationError`.
    public static func measure(
        _ folder: URL,
        root: FileRoot,
        itemLimit: Int = Self.itemLimit
    ) throws -> Self {
        guard root.containsTarget(of: folder) else { throw FileOperationError.outsideRoot }
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard
            let items = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return Self(byteCount: 0, itemCount: 0, isPartial: false) }
        var (byteCount, itemCount): (Int64, Int) = (0, 0)
        while let item = items.nextObject() as? URL {
            try Task.checkCancellation()
            guard itemCount < itemLimit else {
                return Self(byteCount: byteCount, itemCount: itemCount, isPartial: true)
            }
            itemCount += 1
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true {
                byteCount += Int64(values?.fileSize ?? 0)
            }
        }
        return Self(byteCount: byteCount, itemCount: itemCount, isPartial: false)
    }
}
