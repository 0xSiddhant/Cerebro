import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// One rule on the Proto Config tab.
struct ProtoConfigRow: Equatable {
    let title: String
    let mapping: String
    let detail: String
}

/// What the Proto Config tab shows: each rule and how often it has matched.
@MainActor
final class ProtoConfigViewModel {
    private(set) var rows: [ProtoConfigRow] = []

    /// Called after `rows` changes.
    var onChange: (() -> Void)?

    private let decoders: [any BodyDecoder]
    private let store: TransactionStore
    private let socketStore: SocketStore
    private var updates: [Task<Void, Never>] = []

    init(decoders: [any BodyDecoder], store: TransactionStore, socketStore: SocketStore) {
        self.decoders = decoders
        self.store = store
        self.socketStore = socketStore
        refresh()
    }

    deinit {
        updates.forEach { $0.cancel() }
    }

    /// Whether there's anything for the tab to show, since it's hidden when there isn't.
    static func hasMappings(in decoders: [any BodyDecoder]) -> Bool {
        decoders.contains { !$0.mappings.isEmpty }
    }

    /// Match counts change as traffic arrives, so each batch of captured traffic refreshes them.
    func startObserving() {
        guard updates.isEmpty else { return }
        updates = [
            Task { [weak self, store] in
                for await _ in await store.updates() {
                    self?.refresh()
                }
            },
            Task { [weak self, socketStore] in
                for await _ in await socketStore.updates() {
                    self?.refresh()
                }
            },
        ]
    }

    func refresh() {
        let latest = decoders.flatMap(\.mappings).map(Self.row)
        guard latest != rows else { return }
        rows = latest
        onChange?()
    }

    private static func row(for mapping: DecoderMapping) -> ProtoConfigRow {
        let source = mapping.source == .code ? "Code" : "traffic_map.json"
        let matches = mapping.matchCount == 1 ? "1 match" : "\(mapping.matchCount) matches"
        return ProtoConfigRow(
            title: mapping.name ?? mapping.messageType,
            mapping: "\(mapping.matcher) → \(mapping.messageType)",
            detail: "\(mapping.direction) · \(source) · \(matches)"
        )
    }
}
