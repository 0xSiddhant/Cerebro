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

    /// Creates a body.
    public init(
        content: Content,
        byteCount: Int,
        compression: BodyCompression? = nil,
        isDecompressed: Bool = false,
        contentType: String? = nil
    ) {
        self.content = content
        self.byteCount = byteCount
        self.compression = compression
        self.isDecompressed = isDecompressed
        self.contentType = contentType
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
