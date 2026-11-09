import Foundation

#if SWIFT_PACKAGE
import CerebroProtoGeneratorCore
#endif

do {
    try ProtoRuleGenerator.run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
