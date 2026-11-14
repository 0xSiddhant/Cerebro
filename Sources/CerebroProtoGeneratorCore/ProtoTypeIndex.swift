/// Finds the Swift type generated for each proto message, by reading what `.pb.swift` files declare.
struct ProtoTypeIndex {
    private static let packageMarker = "_protobuf_package = \""
    private static let extensionMarker = "extension "
    private static let modifierMarker = "nonisolated "
    private static let nameMarker = "protoMessageName: String = "
    private static let parentMarker = ".protoMessageName"

    private var swiftTypes: [String: String] = [:]

    /// The Swift type for a full proto name, such as `Market_V1_Quote` for `market.v1.Quote`.
    func swiftType(for protoName: String) -> String? {
        swiftTypes[protoName]
    }

    /// Reads one generated file. A message nested in another refers to its parent's name, and is
    /// declared after it, so names are resolved as the file is read.
    mutating func add(generatedSource source: String) {
        var package = ""
        var currentType: String?
        var protoNames: [String: String] = [:]
        for line in source.split(whereSeparator: \.isNewline) {
            if let value = Self.quoted(in: line, after: Self.packageMarker) {
                package = value
            } else if let type = Self.extendedType(in: line) {
                currentType = type
            } else if let currentType, let name = Self.protoName(in: line, package: package, known: protoNames) {
                protoNames[currentType] = name
                swiftTypes[name] = currentType
            }
        }
    }

    /// The type an extension is for. Newer generators write `nonisolated extension`, older ones `extension`.
    private static func extendedType(in line: Substring) -> String? {
        let declaration = line.hasPrefix(modifierMarker) ? line.dropFirst(modifierMarker.count) : line
        guard declaration.hasPrefix(extensionMarker) else { return nil }
        return String(declaration.dropFirst(extensionMarker.count).prefix { $0 != ":" && $0 != " " })
    }

    private static func quoted(in line: Substring, after marker: String) -> String? {
        guard let range = line.range(of: marker) else { return nil }
        return String(line[range.upperBound...].prefix { $0 != "\"" })
    }

    private static func protoName(in line: Substring, package: String, known: [String: String]) -> String? {
        guard let range = line.range(of: nameMarker) else { return nil }
        let expression = line[range.upperBound...]
        guard let literal = quoted(in: expression, after: "\"") else { return nil }
        if expression.hasPrefix("\"") {
            return literal
        }
        if expression.hasPrefix("_protobuf_package") {
            return package + literal
        }
        guard let parent = expression.range(of: parentMarker).map({ String(expression[..<$0.lowerBound]) }) else {
            return nil
        }
        return known[parent].map { $0 + literal }
    }
}
