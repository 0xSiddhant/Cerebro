import Foundation

/// Removes secrets before anything is stored. Case never matters.
struct Redactor: Sendable {
    static let marker = "[redacted]"

    private let headers: Set<String>
    private let jsonKeys: Set<String>
    private let queryParameters: Set<String>

    init(rules: RedactionRules) {
        headers = Set((rules.sensitiveHeaders.map(\.rawValue) + rules.headers).map { $0.lowercased() })
        jsonKeys = Set(rules.jsonKeys.map { $0.lowercased() })
        queryParameters = Set(rules.queryParameters.map { $0.lowercased() })
    }

    /// Whether bodies have to be parsed at capture.
    var redactsJSON: Bool {
        !jsonKeys.isEmpty
    }

    /// Whether text names a configured JSON key, for text that can't be parsed and redacted properly.
    func mentionsJSONKey(in text: String) -> Bool {
        guard !jsonKeys.isEmpty else { return false }
        let lowercased = text.lowercased()
        return jsonKeys.contains { lowercased.contains($0) }
    }

    /// The same check for a body's bytes. Bytes that aren't UTF-8, such as an image's, count as binary and
    /// are left alone. The check also reads the text form-decoded, for a form that has no content type.
    func mentionsJSONKey(in data: Data, isTruncated: Bool) -> Bool {
        guard let text = Self.text(of: data, isTruncated: isTruncated) else { return false }
        return mentionsJSONKey(in: text) || mentionsJSONKey(in: Self.formDecoded(text))
    }

    /// Reads bytes as text. A body cut off at the cap can end partway through a character, which alone
    /// doesn't make it binary. A UTF-8 character is four bytes at most, so that leaves three at most.
    private static func text(of data: Data, isTruncated: Bool) -> String? {
        for cutBytes in 0...(isTruncated ? 3 : 0) {
            if let text = String(data: data.dropLast(cutBytes), encoding: .utf8) {
                return text
            }
        }
        return nil
    }

    /// Replaces the value of each configured field in a form-encoded body. Every other field keeps its
    /// exact bytes, in order.
    func redact(form data: Data) -> Data {
        let separator = UInt8(ascii: "&")
        let fields = data.split(separator: separator, omittingEmptySubsequences: false)
        return Data(fields.map(redacted(field:)).joined(separator: [separator]))
    }

    private func redacted(field: Data) -> Data {
        guard let equals = field.firstIndex(of: UInt8(ascii: "=")),
            let name = String(bytes: field[..<equals], encoding: .utf8),
            jsonKeys.contains(Self.formDecoded(name).lowercased())
        else { return field }
        return field[...equals] + Data(Self.marker.utf8)
    }

    /// Undoes form encoding, where a space can be written as `+`. A malformed escape is left as it is.
    private static func formDecoded(_ text: String) -> String {
        let spaced = text.replacingOccurrences(of: "+", with: " ")
        return spaced.removingPercentEncoding ?? spaced
    }

    func redact(headers fields: [String: String]) -> [NamedValue] {
        fields
            .map { name, value in
                NamedValue(name: name, value: headers.contains(name.lowercased()) ? Self.marker : value)
            }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    func redact(url: URL?) -> URL? {
        guard let url, !queryParameters.isEmpty,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.queryItems = components.queryItems?.map { item in
            queryParameters.contains(item.name.lowercased()) ? URLQueryItem(name: item.name, value: Self.marker) : item
        }
        return components.url ?? url
    }

    /// Lists a URL's query, which has already been through `redact(url:)`.
    func queryParameters(of url: URL?) -> [NamedValue] {
        guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return []
        }
        return items.map { NamedValue(name: $0.name, value: $0.value ?? "") }
    }

    /// Replaces configured keys at any depth of a parsed JSON value.
    func redact(json: Any) -> Any {
        if let object = json as? [String: Any] {
            return object.reduce(into: [String: Any]()) { result, entry in
                result[entry.key] = jsonKeys.contains(entry.key.lowercased()) ? Self.marker : redact(json: entry.value)
            }
        }
        if let array = json as? [Any] {
            return array.map { redact(json: $0) }
        }
        return json
    }
}
