import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// What the dashboard can do with a request's cURL command, the same from every screen.
@MainActor
enum CurlActions {
    static func copy(_ request: CapturedRequest, confirmingIn host: UIView) {
        Task {
            let command = await command(for: request)
            UIPasteboard.general.string = command.text
            DashboardToast.show((["cURL copied."] + command.caveats).joined(separator: " "), in: host)
        }
    }

    /// The menu items that share a request's cURL command. `anchor` is where an iPad points the sheet.
    static func shareActions(
        for request: CapturedRequest,
        from presenter: UIViewController,
        anchor: @escaping @MainActor () -> (any UIPopoverPresentationControllerSourceItem)?
    ) -> [UIAction] {
        func action(_ title: String, icon: String, format: ShareFormat) -> UIAction {
            UIAction(title: title, image: UIImage(systemName: icon)) { [weak presenter] _ in
                guard let presenter else { return }
                Task { @MainActor in
                    let command = await command(for: request)
                    CapturedContentSharing.share(
                        command.text,
                        as: format,
                        fileName: "request-curl.txt",
                        from: presenter,
                        anchor: anchor() ?? presenter.view
                    )
                }
            }
        }
        return [
            action("Share cURL as Text", icon: "text.alignleft", format: .text),
            action("Share cURL as File", icon: "doc", format: .file),
        ]
    }

    /// A body can be large, so the command is built off the main thread.
    private static func command(for request: CapturedRequest) async -> CurlCommand {
        await Task.detached(priority: .userInitiated) { CurlCommand(request: request) }.value
    }
}
