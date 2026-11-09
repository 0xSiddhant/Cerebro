import Foundation
import Testing
@testable import CerebroProtoGeneratorCore

/// The shape protoc-gen-swift writes, trimmed to the lines the generator reads.
private let generatedSource = """
    fileprivate nonisolated let _protobuf_package = "market.v1"

    nonisolated extension Market_V1_Quote: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase {
      public static let protoMessageName: String = _protobuf_package + ".Quote"
    }

    nonisolated extension Market_V1_Quote.Leg: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase {
      public static let protoMessageName: String = Market_V1_Quote.protoMessageName + ".Leg"
    }
    """

private let packagelessSource = """
    extension Ping: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase {
      static let protoMessageName: String = "Ping"
    }
    """

private func index() -> ProtoTypeIndex {
    var index = ProtoTypeIndex()
    index.add(generatedSource: generatedSource)
    index.add(generatedSource: packagelessSource)
    return index
}

private func parse(_ json: String) throws -> TrafficMap {
    try TrafficMap.parse(Data(json.utf8))
}

private func map(rules: String, version: Int = 1) -> String {
    #"{"version":\#(version),"rules":[\#(rules)]}"#
}

private let quoteRule = #"{"name":"Quote","match":{"host":"a.com"},"response":"market.v1.Quote"}"#

@Test func aPackagedMessageResolvesToItsGeneratedType() {
    #expect(index().swiftType(for: "market.v1.Quote") == "Market_V1_Quote")
}

@Test func aNestedMessageResolvesThroughItsParent() {
    #expect(index().swiftType(for: "market.v1.Quote.Leg") == "Market_V1_Quote.Leg")
}

@Test func aMessageWithNoPackageResolves() {
    #expect(index().swiftType(for: "Ping") == "Ping")
}

@Test func anUnknownNameResolvesToNothing() {
    #expect(index().swiftType(for: "market.v1.Missing") == nil)
}

@Test func theDocumentedFormatParses() throws {
    let parsed = try parse(
        map(
            rules: """
                {"name":"Place order","match":{"host":"a.com","path":"/v1/orders"},"methods":["POST"],\
                "request":"a.Req","response":"a.Res"},\
                {"name":"Live","match":{"host":"b.com","pathPrefix":"/v1"},"socket":{"outgoing":"a.Out","incoming":"a.In"}},\
                {"match":{"regex":"^/v1/[0-9]+$"},"framing":{"stripPrefixBytes":5},"response":"a.Res"}
                """
        )
    )

    #expect(parsed.rules.map { $0.messages.count } == [2, 2, 1])
    #expect(parsed.rules[2].framing?.stripPrefixBytes == 5)
}

@Test func anUnsupportedVersionFails() {
    #expect(throws: GeneratorError.invalidMap("version 2 isn't supported, only 1")) {
        try parse(map(rules: quoteRule, version: 2))
    }
}

@Test func malformedJSONFails() {
    #expect(throws: GeneratorError.self) { try parse("{") }
}

@Test func aMissingVersionFails() {
    #expect(throws: GeneratorError.self) { try parse(#"{"rules":[]}"#) }
}

@Test func aRuleWithNoMatcherFails() {
    #expect(throws: GeneratorError.invalidMap("x needs a host, path, pathPrefix or regex")) {
        try parse(map(rules: #"{"name":"x","match":{},"response":"a.B"}"#))
    }
}

@Test func aRuleWithNoMessageFails() {
    #expect(throws: GeneratorError.invalidMap("x names no message for request, response or socket")) {
        try parse(map(rules: #"{"name":"x","match":{"host":"a.com"}}"#))
    }
}

@Test func anUnnamedRuleIsReportedByPosition() {
    #expect(throws: GeneratorError.invalidMap("rule 1 names no message for request, response or socket")) {
        try parse(map(rules: #"{"match":{"host":"a.com"}}"#))
    }
}

@Test func anInvalidRegexFails() {
    #expect(throws: GeneratorError.invalidMap("x has an invalid regex: ([")) {
        try parse(map(rules: #"{"name":"x","match":{"regex":"(["},"response":"a.B"}"#))
    }
}

@Test func aNegativePrefixFails() {
    #expect(throws: GeneratorError.invalidMap("x has a negative stripPrefixBytes")) {
        try parse(map(rules: #"{"name":"x","match":{"host":"a"},"framing":{"stripPrefixBytes":-1},"response":"a.B"}"#))
    }
}

@Test func unknownMessagesFailListingEveryOne() throws {
    let parsed = try parse(
        map(
            rules:
                #"{"match":{"host":"a"},"request":"z.Two","response":"market.v1.Quote"},{"match":{"host":"b"},"response":"a.One"}"#
        )
    )

    #expect(throws: GeneratorError.unknownMessages(["a.One", "z.Two"])) {
        try RuleFileRenderer.render(parsed, index: index())
    }
}

@Test func theRenderedFileImportsWhicheverModuleHasProtoRule() throws {
    let output = try RuleFileRenderer.render(try parse(map(rules: quoteRule)), index: index())

    #expect(output.contains("#if canImport(CerebroProto)\nimport CerebroProto\n#else\nimport Cerebro\n#endif"))
}

@Test func eachMessageBecomesOneFileRule() throws {
    let parsed = try parse(
        map(
            rules:
                #"{"name":"Q","match":{"host":"a.com"},"methods":["GET"],"request":"market.v1.Quote","response":"market.v1.Quote.Leg"}"#
        )
    )

    let output = try RuleFileRenderer.render(parsed, index: index())

    #expect(output.components(separatedBy: "ProtoRule(\n").count == 3)
    #expect(output.contains("direction: .request"))
    #expect(output.contains("messageType: Market_V1_Quote.Leg.self"))
    #expect(output.contains("source: .file"))
    #expect(output.contains(#"methods: ["GET"]"#))
}

@Test func socketDirectionsRender() throws {
    let parsed = try parse(
        map(rules: #"{"match":{"host":"a"},"socket":{"outgoing":"Ping","incoming":"market.v1.Quote"}}"#))

    let output = try RuleFileRenderer.render(parsed, index: index())

    #expect(output.contains("direction: .socketOutgoing"))
    #expect(output.contains("direction: .socketIncoming"))
}

@Test func framingRenders() throws {
    let parsed = try parse(map(rules: #"{"match":{"host":"a"},"framing":{"stripPrefixBytes":5},"response":"Ping"}"#))

    #expect(try RuleFileRenderer.render(parsed, index: index()).contains("stripPrefixBytes: 5"))
}

@Test func quotesAndBackslashesAreEscaped() throws {
    let parsed = try parse(map(rules: #"{"name":"a\"b","match":{"regex":"^/v1/\\d+$"},"response":"Ping"}"#))

    let output = try RuleFileRenderer.render(parsed, index: index())

    #expect(output.contains(#"name: "a\"b""#))
    #expect(output.contains(#"regex: "^/v1/\\d+$""#))
}

@Test func noRulesRenderAnEmptyList() throws {
    let output = try RuleFileRenderer.render(try parse(map(rules: "")), index: index())

    #expect(output.contains("static let generated: [ProtoRule] = []"))
}

@Test func argumentsParseWithRepeatedSources() throws {
    let arguments = try Arguments(["--map", "m.json", "--output", "o.swift", "--sources", "a", "--sources", "b"])

    #expect(arguments.map == "m.json")
    #expect(arguments.output == "o.swift")
    #expect(arguments.sources == ["a", "b"])
}

@Test(arguments: [
    ["--map", "m.json"],
    ["--map", "m.json", "--output", "o.swift"],
    ["--unknown", "x"],
    ["--map"],
])
func badArgumentsFail(arguments: [String]) {
    #expect(throws: GeneratorError.usage(Arguments.usage)) { try Arguments(arguments) }
}

/// A temporary folder holding a map and one generated file, removed when the test ends.
private func withFiles(map contents: String, _ body: (URL) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data(contents.utf8).write(to: folder.appending(path: "traffic_map.json"))
    try Data(generatedSource.utf8).write(to: folder.appending(path: "quote.pb.swift"))
    try body(folder)
}

private func runGenerator(in folder: URL, source: String) throws -> String {
    let output = folder.appending(path: "Rules.swift")
    try ProtoRuleGenerator.run(arguments: [
        "--map", folder.appending(path: "traffic_map.json").path,
        "--output", output.path,
        "--sources", source,
    ])
    return try String(contentsOf: output, encoding: .utf8)
}

@Test func aSingleGeneratedFileCanBeNamedDirectly() throws {
    try withFiles(map: map(rules: quoteRule)) { folder in
        let output = try runGenerator(in: folder, source: folder.appending(path: "quote.pb.swift").path)

        #expect(output.contains("messageType: Market_V1_Quote.self"))
    }
}

@Test func aFolderIsSearchedForGeneratedFiles() throws {
    try withFiles(map: map(rules: quoteRule)) { folder in
        let output = try runGenerator(in: folder, source: folder.path)

        #expect(output.contains("messageType: Market_V1_Quote.self"))
    }
}

@Test func anUnknownMessageFailsTheRunAndWritesNothing() throws {
    try withFiles(map: map(rules: #"{"match":{"host":"a"},"response":"market.v1.Missing"}"#)) { folder in
        #expect(throws: GeneratorError.unknownMessages(["market.v1.Missing"])) {
            _ = try runGenerator(in: folder, source: folder.path)
        }
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "Rules.swift").path))
    }
}
