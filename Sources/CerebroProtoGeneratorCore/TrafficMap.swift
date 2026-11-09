import Foundation

/// The contents of `traffic_map.json`.
struct TrafficMap: Decodable {
    struct Match: Decodable {
        let host: String?
        let path: String?
        let pathPrefix: String?
        let regex: String?
    }

    struct Socket: Decodable {
        let outgoing: String?
        let incoming: String?
    }

    struct Framing: Decodable {
        let stripPrefixBytes: Int?
    }

    struct Rule: Decodable {
        let name: String?
        let match: Match
        let methods: [String]?
        let request: String?
        let response: String?
        let socket: Socket?
        let framing: Framing?
    }

    static let supportedVersion = 1

    let version: Int
    let rules: [Rule]

    /// Reads and checks a map, so a mistake fails the build rather than a rule silently never matching.
    static func parse(_ data: Data) throws -> Self {
        let map: Self
        do {
            map = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw GeneratorError.invalidMap("it isn't valid: \(error)")
        }
        guard map.version == supportedVersion else {
            throw GeneratorError.invalidMap("version \(map.version) isn't supported, only \(supportedVersion)")
        }
        for (index, rule) in map.rules.enumerated() {
            try rule.check(label: rule.name ?? "rule \(index + 1)")
        }
        return map
    }
}

extension TrafficMap.Rule {
    /// Each proto message this rule names, with the direction it applies to.
    var messages: [(direction: String, name: String)] {
        [
            request.map { ("request", $0) },
            response.map { ("response", $0) },
            socket?.outgoing.map { ("socketOutgoing", $0) },
            socket?.incoming.map { ("socketIncoming", $0) },
        ]
        .compactMap { $0 }
    }

    fileprivate func check(label: String) throws {
        guard [match.host, match.path, match.pathPrefix, match.regex].contains(where: { $0 != nil }) else {
            throw GeneratorError.invalidMap("\(label) needs a host, path, pathPrefix or regex")
        }
        guard !messages.isEmpty else {
            throw GeneratorError.invalidMap("\(label) names no message for request, response or socket")
        }
        if let regex = match.regex, (try? NSRegularExpression(pattern: regex)) == nil {
            throw GeneratorError.invalidMap("\(label) has an invalid regex: \(regex)")
        }
        if let bytes = framing?.stripPrefixBytes, bytes < 0 {
            throw GeneratorError.invalidMap("\(label) has a negative stripPrefixBytes")
        }
    }
}

/// Why generation failed. Printed in a form Xcode shows as a build error.
enum GeneratorError: Error, Equatable, CustomStringConvertible {
    case usage(String)
    case invalidMap(String)
    case unknownMessages([String])

    var description: String {
        switch self {
        case .usage(let message):
            return message
        case .invalidMap(let message):
            return "traffic_map.json: \(message)"
        case .unknownMessages(let names):
            let list = names.joined(separator: ", ")
            return "traffic_map.json: no type in the .pb.swift files matches: \(list)"
        }
    }
}
