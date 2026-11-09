import Foundation
import Testing
@testable import Cerebro
@testable import CerebroCore

private final class FakeDecoder: BodyDecoder, @unchecked Sendable {
    private let lock = NSLock()
    private var current: [DecoderMapping]

    init(_ mappings: [DecoderMapping]) {
        current = mappings
    }

    var mappings: [DecoderMapping] {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    func decode(_ body: Data, context: BodyContext) -> Data? { nil }
}

private struct RulelessDecoder: BodyDecoder {
    func decode(_ body: Data, context: BodyContext) -> Data? { nil }
}

private func mapping(
    name: String? = "Quote",
    source: DecoderMapping.Source = .code,
    matchCount: Int = 0
) -> DecoderMapping {
    DecoderMapping(
        name: name,
        matcher: "api.example.com /v1*",
        direction: "Response",
        messageType: "market.v1.Quote",
        source: source,
        matchCount: matchCount
    )
}

@MainActor
private func viewModel(_ decoders: [any BodyDecoder]) -> ProtoConfigViewModel {
    ProtoConfigViewModel(
        decoders: decoders,
        store: TransactionStore(requestLimit: 10),
        socketStore: SocketStore(frameLimit: 10, payloadByteLimit: 1_000)
    )
}

@Test @MainActor func theTabIsHiddenWithNoDecoder() {
    #expect(!ProtoConfigViewModel.hasMappings(in: []))
}

@Test @MainActor func theTabIsHiddenForADecoderWithNoRules() {
    #expect(!ProtoConfigViewModel.hasMappings(in: [RulelessDecoder()]))
}

@Test @MainActor func theTabShowsForADecoderWithRules() {
    #expect(ProtoConfigViewModel.hasMappings(in: [FakeDecoder([mapping()])]))
}

@Test @MainActor func aRowListsMatcherTypeSourceAndCount() throws {
    let row = try #require(viewModel([FakeDecoder([mapping(matchCount: 3)])]).rows.first)

    #expect(row.title == "Quote")
    #expect(row.mapping == "api.example.com /v1* → market.v1.Quote")
    #expect(row.detail == "Response · Code · 3 matches")
}

@Test @MainActor func aFileRuleNamesItsSource() {
    #expect(viewModel([FakeDecoder([mapping(source: .file)])]).rows.first?.detail.contains("traffic_map.json") == true)
}

@Test @MainActor func oneMatchIsSingular() {
    #expect(viewModel([FakeDecoder([mapping(matchCount: 1)])]).rows.first?.detail.hasSuffix("1 match") == true)
}

@Test @MainActor func anUnnamedRuleIsTitledByItsMessage() {
    #expect(viewModel([FakeDecoder([mapping(name: nil)])]).rows.first?.title == "market.v1.Quote")
}

@Test @MainActor func refreshPicksUpNewCountsAndSaysSo() {
    let decoder = FakeDecoder([mapping(matchCount: 0)])
    let model = viewModel([decoder])
    var changes = 0
    model.onChange = { changes += 1 }

    decoder.mappings = [mapping(matchCount: 2)]
    model.refresh()

    #expect(model.rows.first?.detail.hasSuffix("2 matches") == true)
    #expect(changes == 1)
}

@Test @MainActor func refreshWithNoChangeStaysQuiet() {
    let model = viewModel([FakeDecoder([mapping()])])
    var changes = 0
    model.onChange = { changes += 1 }

    model.refresh()

    #expect(changes == 0)
}
