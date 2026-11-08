import UIKit

/// One body, as pretty JSON or raw. A text view lays out long text lazily, so a 1 MB body stays quick.
final class BodyViewerViewController: UIViewController {
    private let viewModel: BodyViewerViewModel
    private let textView = UITextView()
    private let modes = UISegmentedControl(items: ["Pretty", "Raw"])
    private var loading: Task<Void, Never>?
    private lazy var copyButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "doc.on.doc"),
            primaryAction: UIAction { [weak self] _ in self?.copyText() }
        )
        button.accessibilityLabel = "Copy"
        return button
    }()
    private lazy var shareButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            menu: UIMenu(children: [
                UIAction(title: "Share as Text", image: UIImage(systemName: "text.alignleft")) { [weak self] _ in
                    self?.share(as: .text)
                },
                UIAction(title: "Share as File", image: UIImage(systemName: "doc")) { [weak self] _ in
                    self?.share(as: .file)
                },
            ])
        )
        button.accessibilityLabel = "Share"
        return button
    }()

    init(viewModel: BodyViewerViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        title = viewModel.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BodyViewerViewController is built in code")
    }

    override func loadView() {
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        view = textView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        modes.selectedSegmentIndex = BodyViewerViewModel.Mode.pretty.rawValue
        modes.addAction(UIAction { [weak self] _ in self?.showSelectedMode() }, for: .valueChanged)
        navigationItem.titleView = modes
        navigationItem.rightBarButtonItems = [shareButton, copyButton]
        showSelectedMode()
    }

    private func showSelectedMode() {
        let mode = BodyViewerViewModel.Mode(rawValue: modes.selectedSegmentIndex) ?? .raw
        setActionsEnabled(false)
        loading?.cancel()
        loading = Task { [weak self, viewModel] in
            let text = await viewModel.text(for: mode)
            guard !Task.isCancelled else { return }
            self?.textView.text = text
            self?.setActionsEnabled(!text.isEmpty)
        }
    }

    private func setActionsEnabled(_ isEnabled: Bool) {
        copyButton.isEnabled = isEnabled
        shareButton.isEnabled = isEnabled
    }

    private func copyText() {
        UIPasteboard.general.string = textView.text
        DashboardToast.show(viewModel.copyMessage, in: navigationController?.view ?? view)
    }

    private func share(as format: ShareFormat) {
        CapturedContentSharing.share(
            textView.text,
            as: format,
            fileName: viewModel.fileName,
            from: self,
            anchor: shareButton
        )
    }
}
