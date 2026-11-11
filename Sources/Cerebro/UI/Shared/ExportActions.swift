import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// What the dashboard can export besides cURL: one request as JSON, and the session as HAR. Both go
/// through the share sheet, which warns first.
@MainActor
enum ExportActions {
    /// Runs work off the main thread, because an export can cover a whole session of large bodies.
    nonisolated static func build<Output: Sendable>(_ work: @escaping @Sendable () -> Output) async -> Output {
        await Task.detached(priority: .userInitiated, operation: work).value
    }

    /// The menu items that share one request as a JSON document. `anchor` is where an iPad points the sheet.
    static func jsonActions(
        for transaction: HTTPTransaction,
        from presenter: UIViewController,
        anchor: @escaping @MainActor () -> (any UIPopoverPresentationControllerSourceItem)?
    ) -> [UIAction] {
        func action(_ title: String, icon: String, format: ShareFormat) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: icon)) { [weak presenter] _ in
                guard let presenter else { return }
                Task { @MainActor in
                    let json = await build { TransactionExport.json(transaction) }
                    CapturedContentSharing.share(
                        json, as: format, fileName: "request.json", from: presenter, anchor: anchor() ?? presenter.view)
                }
            }
        }
        return [
            action("Share JSON as Text", icon: "curlybraces", format: .text),
            action("Share JSON as File", icon: "doc.text", format: .file),
        ]
    }

    /// Shares every request in the session as one HAR file.
    static func shareHAR(
        of transactions: [HTTPTransaction],
        from presenter: UIViewController,
        anchor: any UIPopoverPresentationControllerSourceItem
    ) {
        guard !transactions.isEmpty else {
            DashboardToast.show("No requests to export.", in: presenter.view)
            return
        }
        Task { @MainActor [weak presenter] in
            let har = await build { TransactionExport.har(transactions) }
            guard let presenter else { return }
            CapturedContentSharing.share(
                har, as: .file, fileName: "cerebro-session.har", from: presenter, anchor: anchor)
        }
    }
}
