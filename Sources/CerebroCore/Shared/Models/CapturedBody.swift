import Foundation

/// A stored request or response body, after the pipeline ran.
public struct CapturedBody: Sendable, Equatable {
    /// What was kept of the body.
    public enum Content: Sendable, Equatable {
        /// The whole body.
        case complete(Data)

        /// The start of a body that was over the cap.
        case truncated(Data)

        /// Nothing, because the body couldn't be redacted.
        case withheld

        /// Nothing, because download task bodies are never stored.
        case notStored
    }

    /// Why a body that should be protobuf wasn't decoded. Such a body shows as hex.
    public enum Undecoded: Sendable, Equatable {
        /// Its content type says protobuf, but no rule matched.
        case noRule

        /// It, or the JSON it decodes to, was over the stored-body cap.
        case truncated

        /// A rule matched, but the bytes didn't decode as that message.
        case failed
    }

    /// What was kept.
    public let content: Content

    /// The size of the whole body, including anything not stored.
    public let byteCount: Int

    /// The compression the app applied, if Cerebro spotted one.
    public let compression: BodyCompression?

    /// Whether Cerebro removed that compression for display.
    public let isDecompressed: Bool

    /// The content type the body arrived with.
    public let contentType: String?

    /// Whether a decoder turned this body into the JSON in `content`.
    public let isDecoded: Bool

    /// The bytes a decoder started from, for the hex view. `nil` when JSON keys are configured, because
    /// a field the app's types don't know is in these bytes but not in the JSON that was redacted.
    public let rawData: Data?

    /// Why this body wasn't decoded, if it should have been.
    public let undecoded: Undecoded?

    /// Creates a body.
    public init(
        content: Content,
        byteCount: Int,
        compression: BodyCompression? = nil,
        isDecompressed: Bool = false,
        contentType: String? = nil,
        isDecoded: Bool = false,
        rawData: Data? = nil,
        undecoded: Undecoded? = nil
    ) {
        self.content = content
        self.byteCount = byteCount
        self.compression = compression
        self.isDecompressed = isDecompressed
        self.contentType = contentType
        self.isDecoded = isDecoded
        self.rawData = rawData
        self.undecoded = undecoded
    }

    /// The stored bytes, if any were kept.
    public var data: Data? {
        switch content {
        case .complete(let data), .truncated(let data): return data
        case .withheld, .notStored: return nil
        }
    }
}

/// A compression format the app applied to a body itself.
public enum BodyCompression: String, Sendable, Equatable {
    /// gzip, which Cerebro can read.
    case gzip

    /// zlib, which Cerebro can read.
    case zlib

    /// zstd, flagged and shown raw.
    case zstd

    /// brotli, flagged and shown raw.
    case brotli
}
