import UIKit

/// One body, as pretty JSON, raw, or a tree for a decoded body. A text view lays out long text lazily,
/// so a 1 MB body stays quick.
final class BodyViewerViewController: UIViewController {
    private static let treeCellIdentifier = "tree"

    private let viewModel: BodyViewerViewModel
    private let textView = UITextView()
    private let treeView = UITableView(frame: .zero, style: .plain)
    private lazy var modes = UISegmentedControl(items: viewModel.modes.map(\.title))
    private var tree: JSONTree?
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
        textView.backgroundColor = DashboardTheme.card
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        treeView.register(UITableViewCell.self, forCellReuseIdentifier: Self.treeCellIdentifier)
        DashboardTheme.style(treeView)
        treeView.dataSource = self
        treeView.delegate = self
        let container = UIView()
        container.backgroundColor = DashboardTheme.card
        for content in [textView, treeView] {
            content.frame = container.bounds
            content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(content)
        }
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        modes.selectedSegmentIndex = 0
        modes.addAction(UIAction { [weak self] _ in self?.showSelectedMode() }, for: .valueChanged)
        navigationItem.titleView = modes
        navigationItem.prompt = viewModel.notice
        navigationItem.rightBarButtonItems = [shareButton, copyButton]
        showSelectedMode()
    }

    private func showSelectedMode() {
        let mode = viewModel.modes[modes.selectedSegmentIndex]
        setActionsEnabled(false)
        loading?.cancel()
        loading = Task { [weak self, viewModel] in
            let text = await viewModel.text(for: mode)
            let tree = mode == .tree ? await viewModel.tree() : nil
            guard !Task.isCancelled else { return }
            self?.show(text: text, tree: tree)
        }
    }

    /// The text stays behind a tree, because it's what copy and share use.
    private func show(text: String, tree: JSONTree?) {
        textView.text = text
        self.tree = tree
        treeView.isHidden = tree == nil
        textView.isHidden = tree != nil
        treeView.reloadData()
        setActionsEnabled(!text.isEmpty)
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
            fileName: viewModel.fileName(for: viewModel.modes[modes.selectedSegmentIndex]),
            warning: viewModel.shareWarning,
            from: self,
            anchor: shareButton
        )
    }
}

extension BodyViewerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        tree?.rows.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.treeCellIdentifier, for: indexPath)
        guard let row = tree?.rows[indexPath.row] else { return cell }
        var content = UIListContentConfiguration.cell()
        content.text = row.key.map { "\($0): \(row.value)" } ?? row.value
        content.textProperties.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        content.directionalLayoutMargins.leading = CGFloat(row.depth) * 16 + 12
        cell.contentConfiguration = content
        cell.accessoryView = row.canExpand ? chevron(isExpanded: row.isExpanded) : nil
        cell.selectionStyle = row.canExpand ? .default : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        tree?.toggle(rowAt: indexPath.row)
        tableView.reloadData()
    }

    private func chevron(isExpanded: Bool) -> UIImageView {
        let view = UIImageView(image: UIImage(systemName: isExpanded ? "chevron.down" : "chevron.right"))
        view.tintColor = DashboardTheme.tertiaryText
        return view
    }
}
