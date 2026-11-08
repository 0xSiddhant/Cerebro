import Foundation

/// Runs one body through the chain: decompress, decode, redact. Every step is optional, and the
/// order is fixed so decoders always receive plain bytes and redaction always sees the result.
struct BodyProcessor: Sendable {
    private struct Working {
        var data: Data
        var isTruncated: Bool
        var compression: BodyCompression?
        var isDecompressed = false
    }

    let limit: Int
    let decoders: [any BodyDecoder]
    let redactor: Redactor

    /// Processes a body. `declared` is the compression named in the request's headers.
    func process(_ raw: RawBody, context: BodyContext, declared: BodyCompression? = nil) -> CapturedBody? {
        guard raw.byteCount > 0 else { return nil }
        let working = decode(decompress(raw, declared: declared), context: context)
        return CapturedBody(
            content: redact(working, context: context),
            byteCount: raw.byteCount,
            compression: working.compression,
            isDecompressed: working.isDecompressed,
            contentType: context.contentType
        )
    }

    private func decompress(_ raw: RawBody, declared: BodyCompression?) -> Working {
        let compression = declared ?? Decompressor.compression(fromMagicBytes: raw.data)
        var working = Working(data: raw.data, isTruncated: raw.isTruncated, compression: compression)
        guard let compression, let output = Decompressor.decompress(raw.data, as: compression, limit: limit) else {
            return working
        }
        working.data = output.data
        working.isTruncated = raw.isTruncated || output.isTruncated
        working.isDecompressed = true
        return working
    }

    private func decode(_ body: Working, context: BodyContext) -> Working {
        guard !body.isTruncated else { return body }
        var working = body
        for decoder in decoders {
            if let decoded = decoder.decode(body.data, context: context) {
                working.data = decoded
                break
            }
        }
        return working
    }

    /// Redaction beats every shortcut: a JSON body that can't be redacted isn't stored at all.
    private func redact(_ body: Working, context: BodyContext) -> CapturedBody.Content {
        let stored: CapturedBody.Content = body.isTruncated ? .truncated(body.data) : .complete(body.data)
        guard redactor.redactsJSON, looksLikeJSON(body.data, contentType: context.contentType) else { return stored }
        guard !body.isTruncated,
            let object = try? JSONSerialization.jsonObject(with: body.data, options: .fragmentsAllowed),
            let redacted = try? JSONSerialization.data(
                withJSONObject: redactor.redact(json: object),
                options: .fragmentsAllowed
            )
        else { return .withheld }
        return .complete(redacted)
    }

    private func looksLikeJSON(_ data: Data, contentType: String?) -> Bool {
        if contentType?.lowercased().contains("json") == true {
            return true
        }
        let first = data.first { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }
        return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
    }
}
