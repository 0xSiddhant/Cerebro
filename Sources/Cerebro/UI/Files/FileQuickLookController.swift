import QuickLook
import UIKit

/// Quick Look for one file, pushed with the tab bar hidden. Editing and markup are off, because the Files
/// tab doesn't change a file's contents. Its own share button stays, because no public API removes it,
/// and it shares without Cerebro's warning.
final class FileQuickLookController: QLPreviewController {
    /// Longest the loading indicator spins if Quick Look never says it's ready.
    private static let loadingLimit = Duration.seconds(6)

    private let file: URL

    /// The first preview can take seconds to appear, on a blank screen.
    private let loading = UIActivityIndicatorView(style: .large)

    init(file: URL) {
        self.file = file
        super.init(nibName: nil, bundle: nil)
        dataSource = self
        delegate = self
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FileQuickLookController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loading.translatesAutoresizingMaskIntoConstraints = false
        loading.startAnimating()
        view.addSubview(loading)
        NSLayoutConstraint.activate([
            loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
        Task { [weak self] in
            try? await Task.sleep(for: Self.loadingLimit)
            self?.loading.stopAnimating()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Quick Look gives no sign that a preview is ready except setting its toolbar. Its content is
        // added above everything else and stays clear until then, so the indicator is kept behind it.
        view.sendSubviewToBack(loading)
        if toolbarItems?.isEmpty == false {
            loading.stopAnimating()
        }
    }
}

extension FileQuickLookController: QLPreviewControllerDataSource {
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        1
    }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        file as NSURL
    }
}

extension FileQuickLookController: QLPreviewControllerDelegate {
    /// Without this, Quick Look offers markup on images and PDFs.
    nonisolated func previewController(
        _ controller: QLPreviewController,
        editingModeFor previewItem: any QLPreviewItem
    ) -> QLPreviewItemEditingMode {
        .disabled
    }
}
