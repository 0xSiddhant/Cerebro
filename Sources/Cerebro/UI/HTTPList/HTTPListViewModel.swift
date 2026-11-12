import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// One line of the HTTP list.
struct HTTPListRow: Equatable, Identifiable {
    let id: UUID
    let method: String
    let path: String
    let detail: String
    let status: String
    let outcome: TransactionOutcome
}

/// The list's filters, in the order the scope bar shows them.
enum HTTPListFilter: Int, CaseIterable {
    case all
    case success
    case clientError
    case serverError
    case failed

    var title: String {
        switch self {
        case .all: return "All"
        case .success: return "2xx"
        case .clientError: return "4xx"
        case .serverError: return "5xx"
        case .failed: return "Failed"
        }
    }

    func includes(_ outcome: TransactionOutcome) -> Bool {
        switch self {
        case .all: return true
        case .success: return outcome == .success
        case .clientError: return outcome == .clientError
        case .serverError: return outcome == .serverError
        case .failed: return outcome == .failed || outcome == .cancelled
        }
    }
}

/// What the HTTP tab shows: newest first, narrowed by the search text and the filter.
@MainActor
final class HTTPListViewModel {
    private(set) var rows: [HTTPListRow] = []

    /// The rows that were already listed and now read differently, such as an event stream that got
    /// more events. The list has to redraw these itself, because their IDs are the same.
    private(set) var changedRowIDs: [UUID] = []

    /// Called after `rows` changes.
    var onChange: (() -> Void)?

    var searchText = "" {
        didSet { refresh() }
    }

    var filter = HTTPListFilter.all {
        didSet { refresh() }
    }

    private let store: TransactionStore
    private var transactions: [HTTPTransaction] = []
    private var updates: Task<Void, Never>?

    init(store: TransactionStore) {
        self.store = store
    }

    deinit {
        updates?.cancel()
    }

    /// Removes every request from the store. Every screen that reads the store hears about it.
    func clear() async {
        await store.removeAll()
    }

    /// Every request in the store, oldest first.
    func sessionTransactions() async -> [HTTPTransaction] {
        await store.transactions
    }

    func startObserving() {
        guard updates == nil else { return }
        updates = Task { [weak self, store] in
            for await transactions in await store.updates() {
                self?.show(transactions)
            }
        }
    }

    func show(_ transactions: [HTTPTransaction]) {
        self.transactions = transactions.reversed()
        refresh()
    }

    func transaction(id: UUID) -> HTTPTransaction? {
        transactions.first { $0.id == id }
    }

    /// The Log Inspector for a request, which follows the store while the request is still open.
    func inspector(id: UUID) -> LogInspectorViewModel? {
        transaction(id: id).map { LogInspectorViewModel(transaction: $0, store: store) }
    }

    private func refresh() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let previous = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        rows =
            transactions
            .filter { filter.includes($0.outcome) && matches($0, query: query) }
            .map(Self.row)
        changedRowIDs = rows.filter { row in previous[row.id].map { $0 != row } ?? false }.map(\.id)
        onChange?()
    }

    private func matches(_ transaction: HTTPTransaction, query: String) -> Bool {
        guard !query.isEmpty else { return true }
        let fields = [
            transaction.request.url?.absoluteString,
            transaction.request.method,
            transaction.response.map { String($0.statusCode) },
        ]
        return fields.contains { $0?.localizedCaseInsensitiveContains(query) == true }
    }

    private static func row(for transaction: HTTPTransaction) -> HTTPListRow {
        let url = transaction.request.url
        var detail = [url?.host].compactMap { $0 }
        if let total = transaction.timing?.total {
            detail.append(DisplayFormat.duration(total))
        }
        if let received = transaction.size?.bytesReceived {
            detail.append(DisplayFormat.bytes(received))
        }
        if let stream = transaction.eventStream {
            detail.append(stream.state == .open ? "SSE live" : "SSE ended")
            detail.append(DisplayFormat.eventCount(stream.eventCount))
        }
        return HTTPListRow(
            id: transaction.id,
            method: transaction.request.method,
            path: url?.path.isEmpty == false ? url?.path ?? "/" : "/",
            detail: detail.joined(separator: " · "),
            status: DisplayFormat.status(of: transaction),
            outcome: transaction.outcome
        )
    }
}
