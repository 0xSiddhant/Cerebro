import Foundation

/// Runs one body through the chain: decompress, decode, redact. Every step is optional, and the
/// order is fixed so decoders always receive plain bytes and redaction always sees the result.
struct BodyProcessor: Sendable {
    private struct Working {
        var data: Data
        var isTruncated: Bool
        var compression: BodyCompression?
        var isDecompressed = false

        /// The bytes a decoder started from, once one has succeeded.
        var decodedFrom: Data?
        var undecoded: CapturedBody.Undecoded?
    }

    let limit: Int
    let decoders: [any BodyDecoder]
    let redactor: Redactor

    /// Processes a body. `declared` is the compression named in the request's headers.
    ///
    /// `detectsCompression` looks for compression in the body's first bytes.
    func process(
        _ raw: RawBody,
        context: BodyContext,
        declared: BodyCompression? = nil,
        detectsCompression: Bool = true
    ) -> CapturedBody? {
        guard raw.byteCount > 0 else { return nil }
        let working = decode(
            decompress(raw, declared: declared, detectsCompression: detectsCompression),
            context: context
        )
        let redaction = redact(working, context: context)
        return CapturedBody(
            content: redaction.content,
            byteCount: raw.byteCount,
            compression: working.compression,
            isDecompressed: working.isDecompressed,
            contentType: context.contentType,
            isDecoded: working.decodedFrom != nil,
            rawData: redaction.didChange ? nil : working.decodedFrom,
            undecoded: working.undecoded
        )
    }

    private func decompress(_ raw: RawBody, declared: BodyCompression?, detectsCompression: Bool) -> Working {
        let detected = detectsCompression ? Decompressor.compression(fromMagicBytes: raw.data) : nil
        let compression = declared ?? detected
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
        var working = body
        guard !body.isTruncated else {
            working.undecoded = isClaimed(context) || context.isProtobuf ? .truncated : nil
            return working
        }
        for decoder in decoders {
            if let decoded = decoder.decode(body.data, context: context) {
                working.data = decoded
                working.decodedFrom = body.data
                return working
            }
        }
        if isClaimed(context) {
            working.undecoded = .failed
        } else if context.isProtobuf {
            working.undecoded = .noRule
        }
        return working
    }

    private func isClaimed(_ context: BodyContext) -> Bool {
        decoders.contains { $0.claims(context) }
    }

    /// Redaction beats every shortcut: a body that can't be redacted isn't stored at all.
    private func redact(_ body: Working, context: BodyContext) -> (content: CapturedBody.Content, didChange: Bool) {
        let stored: CapturedBody.Content = body.isTruncated ? .truncated(body.data) : .complete(body.data)
        guard redactor.redactsJSON else { return (stored, false) }
        // Protobuf that wasn't decoded has no keys to find, so it can't be redacted.
        if body.undecoded != nil {
            return (.withheld, true)
        }
        // JSON comes first, so JSON sent under a form content type is still redacted by key.
        if body.decodedFrom != nil || looksLikeJSON(body.data, contentType: context.contentType) {
            return redactedJSON(body)
        }
        if isFormEncoded(context.contentType) {
            return (body.isTruncated ? .withheld : .complete(redactor.redact(form: body.data)), true)
        }
        return (redactor.mentionsJSONKey(in: body.data, isTruncated: body.isTruncated) ? .withheld : stored, false)
    }

    private func redactedJSON(_ body: Working) -> (content: CapturedBody.Content, didChange: Bool) {
        guard !body.isTruncated,
            let object = try? JSONSerialization.jsonObject(with: body.data, options: .fragmentsAllowed),
            let redacted = try? JSONSerialization.data(
                withJSONObject: redactor.redact(json: object),
                options: .fragmentsAllowed
            )
        else { return (.withheld, true) }
        return (.complete(redacted), redactor.redactsAnything(in: object))
    }

    private func looksLikeJSON(_ data: Data, contentType: String?) -> Bool {
        if contentType?.lowercased().contains("json") == true {
            return true
        }
        let first = data.first { ![0x20, 0x09, 0x0A, 0x0D].contains($0) }
        return first == UInt8(ascii: "{") || first == UInt8(ascii: "[")
    }

    private func isFormEncoded(_ contentType: String?) -> Bool {
        contentType?.lowercased().contains("application/x-www-form-urlencoded") == true
    }
}
