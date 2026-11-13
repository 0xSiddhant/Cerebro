import QuickLook
import UIKit

/// Quick Look for one file, pushed with the tab bar hidden. Editing and markup stay off, because Quick
/// Look only offers them when a delegate allows it and this has none. Its own share button stays,
/// because no public API removes it, and it shares without Cerebro's warning.
final class FileQuickLookController: QLPreviewController {
    private let file: URL

    /// The first preview can take seconds to appear, so this spins behind it until Quick Look draws.
    private let loading = UIActivityIndicatorView(style: .large)

    init(file: URL) {
        self.file = file
        super.init(nibName: nil, bundle: nil)
        dataSource = self
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
        // At the back, so the preview covers it once it's ready.
        view.insertSubview(loading, at: 0)
        NSLayoutConstraint.activate([
            loading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loading.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        loading.stopAnimating()
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
