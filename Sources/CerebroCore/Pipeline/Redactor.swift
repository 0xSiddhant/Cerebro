import Foundation

/// Removes secrets before anything is stored. Case never matters.
struct Redactor: Sendable {
    static let marker = "[redacted]"

    private static let defaultHeaders: Set<String> = ["authorization", "proxy-authorization", "cookie", "set-cookie"]

    private let headers: Set<String>
    private let jsonKeys: Set<String>
    private let queryParameters: Set<String>

    init(rules: RedactionRules) {
        headers = Self.defaultHeaders.union(rules.headers.map { $0.lowercased() })
        jsonKeys = Set(rules.jsonKeys.map { $0.lowercased() })
        queryParameters = Set(rules.queryParameters.map { $0.lowercased() })
    }

    /// Whether bodies have to be parsed at capture.
    var redactsJSON: Bool {
        !jsonKeys.isEmpty
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
