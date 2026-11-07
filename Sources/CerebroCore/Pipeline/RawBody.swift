import Foundation

/// A body as captured, before the pipeline runs. Only ever holds the first `limit` bytes.
struct RawBody: Sendable, Equatable {
    private(set) var data = Data()
    private(set) var byteCount = 0
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    init(data: Data, limit: Int, isTruncatedFrom totalBytes: Int? = nil) {
        self.limit = limit
        self.data = data.prefix(limit)
        self.byteCount = totalBytes ?? data.count
    }

    var isTruncated: Bool {
        byteCount > data.count
    }

    /// Keeps bytes up to the limit, and counts all of them.
    mutating func append(_ chunk: Data) {
        byteCount += chunk.count
        let room = limit - data.count
        if room > 0 {
            data.append(chunk.prefix(room))
        }
    }
}
