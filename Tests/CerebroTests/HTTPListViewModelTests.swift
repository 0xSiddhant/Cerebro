import Foundation
import Testing
@testable import Cerebro

private func transaction(
    method: String = "GET",
    path: String,
    status: Int? = 200,
    failure: CapturedFailure? = nil
) -> HTTPTransaction {
    HTTPTransaction(
        request: CapturedRequest(
            url: URL(string: "https://example.com\(path)"),
            method: method,
            startDate: Date(timeIntervalSince1970: 0)
        ),
        response: status.map { CapturedResponse(statusCode: $0, endDate: Date(timeIntervalSince1970: 1)) },
        failure: failure,
        timing: TransactionTiming(total: 0.12)
    )
}

@MainActor
private func viewModel(_ transactions: [HTTPTransaction]) -> HTTPListViewModel {
    let viewModel = HTTPListViewModel(store: TransactionStore(requestLimit: 10))
    viewModel.show(transactions)
    return viewModel
}

private let timedOut = CapturedFailure(domain: NSURLErrorDomain, code: NSURLErrorTimedOut, description: "timed out")
private let cancelled = CapturedFailure(domain: NSURLErrorDomain, code: NSURLErrorCancelled, description: "cancelled")

@Test @MainActor func showsTheNewestFirst() {
    let model = viewModel([transaction(path: "/old"), transaction(path: "/new")])

    #expect(model.rows.map(\.path) == ["/new", "/old"])
}

@Test @MainActor func rowDescribesItsRequest() throws {
    let row = try #require(viewModel([transaction(method: "POST", path: "/orders", status: 201)]).rows.first)

    #expect(row.method == "POST")
    #expect(row.path == "/orders")
    #expect(row.status == "201")
    #expect(row.outcome == .success)
    #expect(row.detail == "example.com · 120 ms")
}

@Test @MainActor func failedAndCancelledRowsSaySo() {
    let model = viewModel([
        transaction(path: "/a", status: nil, failure: timedOut),
        transaction(path: "/b", status: nil, failure: cancelled),
    ])

    #expect(model.rows.map(\.status) == ["Cancelled", "Failed"])
}

@Test @MainActor func searchMatchesURLMethodAndStatusWhateverTheCase() {
    let model = viewModel([
        transaction(method: "POST", path: "/orders", status: 201),
        transaction(path: "/Quotes", status: 404),
    ])

    model.searchText = "quotes"
    #expect(model.rows.map(\.path) == ["/Quotes"])

    model.searchText = "post"
    #expect(model.rows.map(\.path) == ["/orders"])

    model.searchText = "404"
    #expect(model.rows.map(\.path) == ["/Quotes"])

    model.searchText = "  "
    #expect(model.rows.count == 2)
}

@Test(arguments: [
    (HTTPListFilter.all, ["/failed", "/server", "/client", "/redirect", "/ok"]),
    (HTTPListFilter.success, ["/ok"]),
    (HTTPListFilter.clientError, ["/client"]),
    (HTTPListFilter.serverError, ["/server"]),
    (HTTPListFilter.failed, ["/failed"]),
])
@MainActor func filtersByOutcome(filter: HTTPListFilter, expected: [String]) {
    let model = viewModel([
        transaction(path: "/ok", status: 200),
        transaction(path: "/redirect", status: 302),
        transaction(path: "/client", status: 404),
        transaction(path: "/server", status: 500),
        transaction(path: "/failed", status: nil, failure: timedOut),
    ])

    model.filter = filter

    #expect(model.rows.map(\.path) == expected)
}

@Test @MainActor func searchAndFilterCombine() {
    let model = viewModel([transaction(path: "/a", status: 500), transaction(path: "/b", status: 500)])

    model.filter = .serverError
    model.searchText = "/b"

    #expect(model.rows.map(\.path) == ["/b"])
}

@Test @MainActor func changesAreReported() {
    let model = viewModel([])
    var changes = 0
    model.onChange = { changes += 1 }

    model.show([transaction(path: "/a")])
    model.searchText = "a"
    model.filter = .success

    #expect(changes == 3)
}

@Test @MainActor func findsATransactionByItsRow() throws {
    let first = transaction(path: "/a")
    let model = viewModel([first, transaction(path: "/b")])

    #expect(model.transaction(id: first.id) == first)
}

@Test @MainActor func picksUpLiveUpdatesFromTheStore() async throws {
    let store = TransactionStore(requestLimit: 10, updateInterval: .milliseconds(10))
    let model = HTTPListViewModel(store: store)
    model.startObserving()

    await store.append(transaction(path: "/live"))

    for _ in 0..<100 where model.rows.isEmpty {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(model.rows.map(\.path) == ["/live"])
}
