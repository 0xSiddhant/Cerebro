import UIKit

/// How captured text leaves through the share sheet.
enum ShareFormat {
    /// Plain text, for Notes, Messages and the like.
    case text

    /// A file, for Save to Files, AirDrop and the like.
    case file
}

/// Shares captured text through the system share sheet, always with the privacy warning first.
@MainActor
enum CapturedContentSharing {
    static func share(
        _ text: String,
        as format: ShareFormat,
        fileName: String,
        from presenter: UIViewController,
        anchor: any UIPopoverPresentationControllerSourceItem
    ) {
        let warning = UIAlertController(
            title: "Share captured data?",
            message: "It can contain personal data or secrets that Cerebro didn't redact.",
            preferredStyle: .alert
        )
        warning.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        warning.addAction(
            UIAlertAction(title: "Share", style: .default) { [weak presenter] _ in
                guard let presenter else { return }
                Task { await presentSheet(text, as: format, fileName: fileName, from: presenter, anchor: anchor) }
            }
        )
        presenter.present(warning, animated: true)
    }

    private static func presentSheet(
        _ text: String,
        as format: ShareFormat,
        fileName: String,
        from presenter: UIViewController,
        anchor: any UIPopoverPresentationControllerSourceItem
    ) async {
        var items: [Any] = [text]
        var folder: URL?
        if format == .file {
            guard let file = await writeTemporaryFile(text, named: fileName) else {
                DashboardToast.show("Couldn't create the file.", in: presenter.view)
                return
            }
            items = [file]
            folder = file.deletingLastPathComponent()
        }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // An iPad shows the sheet as a popover, and presenting one with no anchor crashes.
        sheet.popoverPresentationController?.sourceItem = anchor
        sheet.completionWithItemsHandler = { activity, completed, _, _ in
            // With an activity and no completion, the sheet is still open for another choice.
            guard completed || activity == nil, let folder else { return }
            Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: folder) }
        }
        presenter.present(sheet, animated: true)
    }

    private static func writeTemporaryFile(_ text: String, named name: String) async -> URL? {
        await Task.detached(priority: .userInitiated) {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let file = folder.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data(text.utf8).write(to: file)
                return file
            } catch {
                return nil
            }
        }
        .value
    }
}
