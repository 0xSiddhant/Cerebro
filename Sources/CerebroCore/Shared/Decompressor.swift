import Compression
import Foundation

/// Spots compressed bodies and reads gzip and zlib, without ever producing more than the limit.
enum Decompressor {
    /// The result of reading a compressed body.
    struct Output: Equatable {
        let data: Data
        let isTruncated: Bool
    }

    private static let bufferSize = 65_536

    /// Small, because a stream cut off partway loses whatever chunk it was filling.
    private static let chunkSize = 4_096

    /// Names the compression in a `Content-Encoding` value.
    static func compression(fromContentEncoding value: String?) -> BodyCompression? {
        switch value?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "gzip", "x-gzip": return .gzip
        case "deflate": return .zlib
        case "zstd": return .zstd
        case "br": return .brotli
        default: return nil
        }
    }

    /// Names the compression from a body's first bytes. Brotli has no magic bytes.
    static func compression(fromMagicBytes data: Data) -> BodyCompression? {
        let header = [UInt8](data.prefix(4))
        if header.starts(with: [0x1F, 0x8B, 0x08]) {
            return .gzip
        }
        if header.starts(with: [0x28, 0xB5, 0x2F, 0xFD]) {
            return .zstd
        }
        if header.count >= 2, header[0] == 0x78, [0x01, 0x5E, 0x9C, 0xDA].contains(header[1]) {
            return .zlib
        }
        return nil
    }

    /// Reads a body, stopping once the output passes the limit. Returns `nil` if it can't be read.
    static func decompress(_ data: Data, as compression: BodyCompression, limit: Int) -> Output? {
        guard let start = deflateStart(in: data, compression: compression) else { return nil }
        var input = data.dropFirst(start)
        let filter = try? InputFilter<Data>(.decompress, using: .zlib, bufferCapacity: bufferSize) { length in
            let chunk = input.prefix(length)
            input = input.dropFirst(length)
            return chunk.isEmpty ? nil : Data(chunk)
        }
        guard let filter else { return nil }

        var output = Data()
        var isIncomplete = false
        while output.count <= limit {
            do {
                guard let chunk = try filter.readData(ofLength: chunkSize), !chunk.isEmpty else { break }
                output.append(chunk)
            } catch {
                // A cut-off or corrupt stream fails partway. Keep what came out, if anything did.
                isIncomplete = true
                break
            }
        }
        guard !output.isEmpty else { return nil }
        return Output(data: output.prefix(limit), isTruncated: isIncomplete || output.count > limit)
    }

    /// Finds where the raw DEFLATE stream starts, after any wrapper's header.
    private static func deflateStart(in data: Data, compression: BodyCompression) -> Int? {
        switch compression {
        case .gzip: return gzipHeaderLength(data)
        case .zlib: return data.count > 2 ? 2 : nil
        case .zstd, .brotli: return nil
        }
    }

    private static func gzipHeaderLength(_ data: Data) -> Int? {
        let bytes = [UInt8](data.prefix(bufferSize))
        guard bytes.count > 10 else { return nil }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 {
            guard index + 2 <= bytes.count else { return nil }
            index += 2 + Int(bytes[index]) + Int(bytes[index + 1]) << 8
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {
            guard let end = bytes[min(index, bytes.count)...].firstIndex(of: 0) else { return nil }
            index = end + 1
        }
        if flags & 0x02 != 0 {
            index += 2
        }
        return index < data.count ? index : nil
    }
}
