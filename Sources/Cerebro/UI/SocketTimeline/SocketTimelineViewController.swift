import UIKit

/// One socket as a conversation, following the newest frame while the reader is at the bottom.
final class SocketTimelineViewController: UITableViewController {
    private static let bottomTolerance: CGFloat = 40

    private let viewModel: SocketTimelineViewModel

    init(viewModel: SocketTimelineViewModel) {
        self.viewModel = viewModel
        super.init(style: .plain)
        title = viewModel.title
        // The floating tab bar would otherwise cover the newest frames.
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SocketTimelineViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.separatorStyle = .none
        tableView.allowsSelection = true
        tableView.register(SocketFrameCell.self, forCellReuseIdentifier: SocketFrameCell.reuseIdentifier)
        tableView.register(SocketEventCell.self, forCellReuseIdentifier: SocketEventCell.reuseIdentifier)
        viewModel.onChange = { [weak self] in self?.showLatest() }
        viewModel.startObserving()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollToNewest()
    }

    private var isAtBottom: Bool {
        let visibleBottom = tableView.contentOffset.y + tableView.bounds.height - tableView.adjustedContentInset.bottom
        return visibleBottom >= tableView.contentSize.height - Self.bottomTolerance
    }

    private func showLatest() {
        let wasAtBottom = isAtBottom
        tableView.reloadData()
        if wasAtBottom {
            scrollToNewest()
        }
    }

    private func scrollToNewest() {
        guard !viewModel.items.isEmpty else { return }
        tableView.layoutIfNeeded()
        tableView.scrollToRow(at: IndexPath(row: viewModel.items.count - 1, section: 0), at: .bottom, animated: false)
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.items.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch viewModel.row(at: indexPath.row) {
        case .frame(let row):
            let cell = tableView.dequeueReusableCell(withIdentifier: SocketFrameCell.reuseIdentifier, for: indexPath)
            (cell as? SocketFrameCell)?.show(row)
            return cell
        case .event(let text):
            let cell = tableView.dequeueReusableCell(withIdentifier: SocketEventCell.reuseIdentifier, for: indexPath)
            (cell as? SocketEventCell)?.show(text)
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        guard case .frame(let row) = viewModel.row(at: indexPath.row), let body = row.body else { return }
        let title = row.isSent ? "Sent frame" : "Received frame"
        let viewer = BodyViewerViewController(viewModel: BodyViewerViewModel(title: title, body: body))
        navigationController?.pushViewController(viewer, animated: true)
    }
}
