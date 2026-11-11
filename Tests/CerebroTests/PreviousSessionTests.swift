import Foundation
import Testing
import UIKit
@testable import Cerebro

private func request(_ path: String) -> HTTPTransaction {
    HTTPTransaction(
        request: CapturedRequest(url: URL(string: "https://example.com\(path)"), method: "GET", startDate: Date()))
}

@Test @MainActor func onlyCerebrosOwnNotificationOpensTheDashboardAndOnlyWhenTheTriggerIsOn() {
    let own = NotificationTrigger.identifier

    #expect(NotificationTrigger.opensDashboard(identifier: own, isEnabled: true))
    #expect(!NotificationTrigger.opensDashboard(identifier: own, isEnabled: false))
    #expect(!NotificationTrigger.opensDashboard(identifier: "com.example.order-shipped", isEnabled: true))
}

@Test @MainActor func aSavedSessionOpensInTheSameListReadOnly() async throws {
    let store = TransactionStore(requestLimit: 10)
    await store.append(request("/saved"))
    let list = HTTPListViewController(
        viewModel: HTTPListViewModel(store: store), previousSessionTitle: "Previous: 11 Nov, 14:02")

    list.loadViewIfNeeded()

    #expect(list.title == "Previous: 11 Nov, 14:02")
    // Export only: a saved session can't be cleared, and has no earlier sessions of its own.
    #expect(list.navigationItem.rightBarButtonItems?.count == 1)
    #expect(list.navigationItem.rightBarButtonItems?.first?.accessibilityLabel == "Export")
    #expect(list.hidesBottomBarWhenPushed)
}

@Test @MainActor func theLiveListOffersClearAndNoHistoryWithoutAnArchive() {
    let list = HTTPListViewController(viewModel: HTTPListViewModel(store: TransactionStore(requestLimit: 10)))

    list.loadViewIfNeeded()

    #expect(list.title == "HTTP")
    #expect(list.navigationItem.rightBarButtonItems?.compactMap(\.accessibilityLabel) == ["Export", "Clear requests"])
    #expect(!list.hidesBottomBarWhenPushed)
}

@Test @MainActor func aSavedSocketSessionHasNoHistoryButtonOfItsOwn() {
    let store = SocketStore(frameLimit: 10, payloadByteLimit: 1_000)
    let list = SocketListViewController(
        viewModel: SocketListViewModel(store: store), store: store, previousSessionTitle: "Previous: 11 Nov, 14:02")

    list.loadViewIfNeeded()

    #expect(list.title == "Previous: 11 Nov, 14:02")
    #expect(list.navigationItem.rightBarButtonItem == nil)
    #expect(list.hidesBottomBarWhenPushed)
}

@Test func aSessionStartIsShortEnoughForATitle() {
    let text = DisplayFormat.sessionStart(Date(timeIntervalSince1970: 1_700_000_000))

    #expect(!text.isEmpty)
    #expect(text.count < 24)
}
