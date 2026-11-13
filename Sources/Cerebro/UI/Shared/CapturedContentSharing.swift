import UIKit

/// How captured text leaves through the share sheet.
enum ShareFormat {
    /// Plain text, for Notes, Messages and the like.
    case text

    /// A file, for Save to Files, AirDrop and the like.
    case file
}

/// What the warning before a share says, which depends on what's leaving the device.
enum ShareWarning {
    /// Traffic, which only the developer's redaction rules changed.
    case capturedData

    /// The app's files, which Cerebro shows and shares exactly as they are on disk.
    case files

    var title: String {
        switch self {
        case .capturedData: return "Share captured data?"
        case .files: return "Share these files?"
        }
    }

    var message: String {
        switch self {
        case .capturedData: return "It can contain personal data or secrets that Cerebro didn't redact."
        case .files: return "They can contain personal data or secrets. Cerebro never redacts files."
        }
    }
}

/// Files ready for the share sheet, and a temporary folder to remove once it closes.
struct PreparedShare: Sendable {
    let files: [URL]
    let temporaryFolder: URL?
}

/// Shares captured text or the app's files through the system share sheet, always with the privacy
/// warning first.
@MainActor
enum CapturedContentSharing {
    static func share(
        _ text: String,
        as format: ShareFormat,
        fileName: String,
        warning: ShareWarning = .capturedData,
        from presenter: UIViewController,
        anchor: any UIPopoverPresentationControllerSourceItem
    ) {
        confirm(warning, from: presenter) { presenter in
            guard format == .file else {
                presentSheet(items: [text], temporaryFolder: nil, from: presenter, anchor: anchor)
                return
            }
            guard let file = await writeTemporaryFile(text, named: fileName) else {
                DashboardToast.show("Couldn't create the file.", in: presenter.view)
                return
            }
            presentSheet(
                items: [file], temporaryFolder: file.deletingLastPathComponent(), from: presenter, anchor: anchor)
        }
    }

    /// Shares files from disk. `prepare` runs off the main thread once the developer agrees, so a folder
    /// can be zipped there.
    static func shareFiles(
        from presenter: UIViewController,
        anchor: any UIPopoverPresentationControllerSourceItem,
        prepare: @escaping @Sendable () throws -> PreparedShare
    ) {
        confirm(.files, from: presenter) { presenter in
            let result = await Task.detached(priority: .userInitiated) { Result(catching: prepare) }.value
            switch result {
            case .success(let prepared):
                presentSheet(
                    items: prepared.files, temporaryFolder: prepared.temporaryFolder, from: presenter, anchor: anchor)
            case .failure(let error):
                FileAlerts.showFailure(error, from: presenter)
            }
        }
    }

    private static func confirm(
        _ warning: ShareWarning,
        from presenter: UIViewController,
        then share: @escaping @MainActor (UIViewController) async -> Void
    ) {
        let alert = UIAlertController(title: warning.title, message: warning.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Share", style: .default) { [weak presenter] _ in
                guard let presenter else { return }
                Task { await share(presenter) }
            }
        )
        presenter.present(alert, animated: true)
    }

    private static func presentSheet(
        items: [Any],
        temporaryFolder: URL?,
        from presenter: UIViewController,
        anchor: any UIPopoverPresentationControllerSourceItem
    ) {
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        // An iPad shows the sheet as a popover, and presenting one with no anchor crashes.
        sheet.popoverPresentationController?.sourceItem = anchor
        sheet.completionWithItemsHandler = { activity, completed, _, _ in
            // With an activity and no completion, the sheet is still open for another choice.
            guard completed || activity == nil, let temporaryFolder else { return }
            Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: temporaryFolder) }
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
