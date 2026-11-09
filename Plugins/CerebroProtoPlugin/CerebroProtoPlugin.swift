import Foundation
import PackagePlugin

/// Turns an app target's `traffic_map.json` into `ProtoRule.generated` when it builds.
@main
struct CerebroProtoPlugin {
    private static let mapFileName = "traffic_map.json"
    private static let outputFileName = "CerebroProtoRules.generated.swift"

    /// Builds the command, or fails naming every place it looked for the map.
    fileprivate func command(
        tool: PluginContext.Tool,
        files: [Path],
        folders: [Path],
        workDirectory: Path
    ) throws -> Command {
        let candidates = files.filter { $0.lastComponent == Self.mapFileName }
            + folders.map { $0.appending(Self.mapFileName) }
        guard let map = candidates.first(where: { FileManager.default.fileExists(atPath: $0.string) }) else {
            let searched = folders.map(\.string).joined(separator: ", ")
            throw PluginError.missingMap("\(Self.mapFileName) wasn't found in the target or in \(searched)")
        }
        let generated = files.filter { $0.lastComponent.hasSuffix(".pb.swift") }
        let output = workDirectory.appending(Self.outputFileName)
        return .buildCommand(
            displayName: "Generating Cerebro proto rules",
            executable: tool.path,
            arguments: ["--map", map.string, "--output", output.string]
                + (generated.isEmpty ? folders.map(\.string) : generated.map(\.string)).flatMap { ["--sources", $0] },
            inputFiles: [map] + generated,
            outputFiles: [output]
        )
    }
}

private enum PluginError: Error, CustomStringConvertible {
    case missingMap(String)

    var description: String {
        switch self {
        case .missingMap(let message): return message
        }
    }
}

extension CerebroProtoPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }
        return [
            try command(
                tool: try context.tool(named: "CerebroProtoGenerator"),
                files: target.sourceFiles.map(\.path),
                folders: [target.directory, context.package.directory],
                workDirectory: context.pluginWorkDirectory
            )
        ]
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension CerebroProtoPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        [
            try command(
                tool: try context.tool(named: "CerebroProtoGenerator"),
                files: target.inputFiles.map(\.path),
                folders: [context.xcodeProject.directory],
                workDirectory: context.pluginWorkDirectory
            )
        ]
    }
}
#endif
