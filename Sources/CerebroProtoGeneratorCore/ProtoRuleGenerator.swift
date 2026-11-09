import Foundation

/// Writes `ProtoRule.generated` from `traffic_map.json` and the app's `.pb.swift` files.
public enum ProtoRuleGenerator {
    /// Runs the generator with command-line arguments, throwing an error fit to show as a build failure.
    public static func run(arguments rawArguments: [String]) throws {
        let arguments = try Arguments(rawArguments)
        let map = try TrafficMap.parse(Data(contentsOf: URL(fileURLWithPath: arguments.map)))
        var index = ProtoTypeIndex()
        for file in arguments.generatedFiles {
            index.add(generatedSource: try String(contentsOfFile: file, encoding: .utf8))
        }
        let output = try RuleFileRenderer.render(map, index: index)
        // Leaving an unchanged file alone keeps the app's build from recompiling it.
        if (try? String(contentsOfFile: arguments.output, encoding: .utf8)) != output {
            try output.write(toFile: arguments.output, atomically: true, encoding: .utf8)
        }
    }
}
