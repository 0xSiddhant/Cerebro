import UIKit

/// One body, as pretty JSON or raw. A text view lays out long text lazily, so a 1 MB body stays quick.
final class BodyViewerViewController: UIViewController {
    private let viewModel: BodyViewerViewModel
    private let textView = UITextView()
    private let modes = UISegmentedControl(items: ["Pretty", "Raw"])
    private var loading: Task<Void, Never>?

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
        textView.accessibilityIdentifier = "cerebro.body"
        view = textView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        modes.selectedSegmentIndex = BodyViewerViewModel.Mode.pretty.rawValue
        modes.addAction(UIAction { [weak self] _ in self?.showSelectedMode() }, for: .valueChanged)
        navigationItem.titleView = modes
        showSelectedMode()
    }

    private func showSelectedMode() {
        let mode = BodyViewerViewModel.Mode(rawValue: modes.selectedSegmentIndex) ?? .raw
        loading?.cancel()
        loading = Task { [weak self, viewModel] in
            let text = await viewModel.text(for: mode)
            guard !Task.isCancelled else { return }
            self?.textView.text = text
        }
    }
}
