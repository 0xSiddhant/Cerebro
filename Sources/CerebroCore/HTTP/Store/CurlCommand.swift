import Foundation

/// A captured request as a cURL command. Redaction ran before storage, so it never holds a redacted value.
public struct CurlCommand: Sendable, Equatable {
    /// How a body reaches `curl`.
    private struct Payload {
        /// What runs before `curl`, when the body is piped in.
        var input = ""
        let option: String
    }

    /// The largest body passed as an argument. Linux refuses one argument over 128 KB, and macOS a
    /// whole command over 1 MB. `printf` is built into the shell, so piping avoids both limits.
    private static let argumentByteLimit = 100_000

    /// The command, ready to paste into a terminal.
    public let text: String

    /// Sentences saying where the command differs from the original request, if it does.
    public let caveats: [String]

    /// Builds the command. Call it off the main thread, because a body can be large.
    public init(request: CapturedRequest) {
        var caveats: [String] = []
        let payload = Self.payload(of: request.body, caveats: &caveats)

        var parts = [
            "curl" + Self.methodOption(request.method, hasBody: payload != nil) + " "
                + Self.quoted(request.url?.absoluteString ?? "")
        ]
        parts += request.headers
            .filter { Self.isReplayable($0, body: request.body) }
            .map { "-H " + Self.quoted($0.value.isEmpty ? "\($0.name);" : "\($0.name): \($0.value)") }
        if let payload {
            parts.append(payload.option)
        }

        text = (payload?.input ?? "") + parts.joined(separator: " \\\n  ")
        if text.contains(Redactor.marker) || text.contains("%5Bredacted%5D") {
            caveats.append("Redacted values are placeholders.")
        }
        self.caveats = caveats
    }

    private static func methodOption(_ method: String, hasBody: Bool) -> String {
        if method == "HEAD", !hasBody { return " --head" }
        return method == "GET" && !hasBody ? "" : " -X \(method)"
    }

    /// `curl` works out the length itself, and a body Cerebro decompressed is no longer compressed.
    private static func isReplayable(_ header: NamedValue, body: CapturedBody?) -> Bool {
        let name = header.name.lowercased()
        return name != "content-length" && !(name == "content-encoding" && body?.isDecompressed == true)
    }

    private static func payload(of body: CapturedBody?, caveats: inout [String]) -> Payload? {
        guard let body else { return nil }
        switch body.content {
        case .withheld:
            caveats.append("The body isn't included, because it couldn't be redacted.")
        case .notStored:
            caveats.append("The body isn't included, because it wasn't stored.")
        case .complete(let data), .truncated(let data):
            if case .truncated = body.content {
                caveats.append("The body was cut off at capture, so it's incomplete.")
            }
            // The stored JSON isn't what the server expects, so replay the original bytes when they were kept.
            if body.isDecoded, body.rawData == nil {
                caveats.append("The body is decoded JSON, not the bytes the app sent, so a server may reject it.")
            }
            let bytes = body.rawData ?? data
            return bytes.isEmpty ? nil : payload(of: bytes)
        }
        return nil
    }

    private static func payload(of data: Data) -> Payload {
        guard let text = String(data: data, encoding: .utf8), survivesPasting(text) else {
            let encoded = quoted(data.base64EncodedString())
            return Payload(input: "printf %s \(encoded) | base64 --decode | ", option: "--data-binary @-")
        }
        guard data.count <= argumentByteLimit else {
            return Payload(input: "printf %s \(quoted(text)) | ", option: "--data-binary @-")
        }
        return Payload(option: "--data-raw \(quoted(text))")
    }

    /// Bytes such as protobuf's can be valid UTF-8 and still hold control characters. Copying and pasting
    /// them into a terminal drops or changes them, so only newlines are safe to leave in the command.
    private static func survivesPasting(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { $0 == "\n" || $0.properties.generalCategory != .control }
    }

    private static func quoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
