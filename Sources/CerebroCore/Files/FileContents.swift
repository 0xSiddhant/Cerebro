import Foundation

/// What a file holds, which decides the viewer it opens in.
public enum FileFormat: Sendable, Equatable {
    /// A property list, binary or XML. Shown as JSON, because Quick Look shows a binary one as bytes.
    case propertyList

    /// JSON, pretty-printed, because Quick Look shows it on one line.
    case json

    /// Something Quick Look renders well: images, PDF, audio, video, web pages, rich text, CSV, office
    /// and iWork documents, and plain text.
    case document

    /// Anything else, such as SQLite or a file with no extension, shown as text if it's UTF-8 and as hex
    /// if it isn't.
    case other

    private static let documentExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp", "ico", "svg",
        "pdf",
        "mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac",
        "mp4", "mov", "m4v", "3gp",
        "html", "htm", "rtf", "csv",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key",
        "txt", "text", "md", "markdown",
    ]

    /// How many bytes from the start of a file the format looks at.
    static let headerLength = 64

    /// The format of a file, from its extension and then its first bytes. Pass an empty header to go
    /// by the name alone.
    public init(name: String, header: Data) {
        let pathExtension = URL(fileURLWithPath: name).pathExtension.lowercased()
        if pathExtension == "plist" || Self.isPropertyList(header) {
            self = .propertyList
        } else if pathExtension == "json" {
            self = .json
        } else if Self.documentExtensions.contains(pathExtension) {
            self = .document
        } else {
            self = .other
        }
    }

    private static func isPropertyList(_ header: Data) -> Bool {
        if header.starts(with: Data("bplist00".utf8)) {
            return true
        }
        guard let text = String(data: header.prefix(headerLength), encoding: .utf8) else { return false }
        return text.hasPrefix("<?xml") && (text.contains("<!DOCTYPE plist") || text.contains("<plist"))
    }
}

/// Reads files for the Body Viewer, never more than the stored-body cap.
public enum FileContents {
    /// A file's contents as a body the Body Viewer can show. A property list within `limit` is converted
    /// to JSON, and one over it is cut off and shown as hex. Anything else is read up to `limit` and
    /// shown as text or hex. `asRaw` skips the conversion, to see a file's bytes as they are. It blocks,
    /// so call it off the main thread.
    public static func body(of file: URL, root: FileRoot, limit: Int, asRaw: Bool = false) throws -> CapturedBody {
        guard root.containsTarget(of: file) else { throw FileOperationError.outsideRoot }
        let limit = max(limit, 0)
        let (data, totalBytes) = try read(file, limit: limit)
        let isComplete = data.count == totalBytes
        let format = FileFormat(name: file.lastPathComponent, header: data.prefix(FileFormat.headerLength))
        if !asRaw, format == .propertyList {
            guard isComplete else {
                return CapturedBody(content: .truncated(data), byteCount: totalBytes, undecoded: .truncated)
            }
            if let json = propertyListJSON(data) {
                return CapturedBody(
                    content: .complete(json), byteCount: json.count, contentType: "application/json", isDecoded: true)
            }
        }
        guard isComplete else {
            return CapturedBody(content: .truncated(trimmedToCharacter(data)), byteCount: totalBytes)
        }
        return CapturedBody(content: .complete(data), byteCount: totalBytes)
    }

    /// The first `limit` bytes of a file, and its whole size.
    static func read(_ file: URL, limit: Int) throws -> (data: Data, totalBytes: Int) {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let totalBytes = Int(try handle.seekToEnd())
        try handle.seek(toOffset: 0)
        let data = try handle.read(upToCount: min(limit, totalBytes)) ?? Data()
        return (data, max(totalBytes, data.count))
    }

    /// A property list as JSON. A value JSON can't hold is written as text: a date in ISO 8601, data as
    /// Base64, and anything else, such as the references in an `NSKeyedArchiver` archive, as its
    /// description. `nil` if the bytes aren't a property list.
    static func propertyListJSON(_ data: Data) -> Data? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return nil }
        let value = jsonValue(of: object)
        // JSONSerialization raises an Objective-C exception for a value it can't write, which `try?`
        // doesn't catch and which would end the app, so it's checked first.
        guard value is String || value is NSNumber || JSONSerialization.isValidJSONObject(value) else { return nil }
        return try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
    }

    private static func jsonValue(of value: Any) -> Any {
        switch value {
        case let dictionary as [String: Any]: return dictionary.mapValues(jsonValue)
        case let array as [Any]: return array.map(jsonValue)
        case let text as String: return text
        case let date as Date: return date.formatted(.iso8601)
        case let data as Data: return data.base64EncodedString()
        case let number as NSNumber:
            // JSON has no infinity or NaN.
            let isBoolean = CFGetTypeID(number) == CFBooleanGetTypeID()
            return isBoolean || number.doubleValue.isFinite ? number : number.stringValue
        default: return String(describing: value)
        }
    }

    /// Drops a character the cap cut in half, so text that was cut off still reads as text.
    private static func trimmedToCharacter(_ data: Data) -> Data {
        // A UTF-8 character is at most four bytes, so at most three of one can be left over.
        (0...min(3, data.count)).lazy.map { data.dropLast($0) }.first { String(data: $0, encoding: .utf8) != nil }
            ?? data
    }
}
