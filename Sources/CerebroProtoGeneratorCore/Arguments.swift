import Foundation

/// What the generator was asked to do.
struct Arguments: Equatable {
    static let usage = "usage: cerebro-proto-gen --map <traffic_map.json> --output <file.swift> --sources <path>..."

    let map: String
    let output: String
    let sources: [String]

    init(_ arguments: [String]) throws {
        var map: String?
        var output: String?
        var sources: [String] = []
        var remaining = arguments[...]
        while let flag = remaining.popFirst() {
            guard let value = remaining.popFirst() else { throw GeneratorError.usage(Self.usage) }
            switch flag {
            case "--map": map = value
            case "--output": output = value
            case "--sources": sources.append(value)
            default: throw GeneratorError.usage(Self.usage)
            }
        }
        guard let map, let output, !sources.isEmpty else { throw GeneratorError.usage(Self.usage) }
        self.map = map
        self.output = output
        self.sources = sources
    }

    /// Every `.pb.swift` file named directly or found under a folder.
    var generatedFiles: [String] {
        sources.flatMap { source -> [String] in
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: source, isDirectory: &isFolder), isFolder.boolValue,
                let files = FileManager.default.enumerator(atPath: source)
            else { return [source] }
            return files.compactMap { $0 as? String }.filter { $0.hasSuffix(".pb.swift") }
                .map { (source as NSString).appendingPathComponent($0) }
        }
    }
}
