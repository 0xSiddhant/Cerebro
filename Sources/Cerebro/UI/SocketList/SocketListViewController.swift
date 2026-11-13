import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// The Sockets tab: every captured socket, newest first.
final class SocketListViewController: UITableViewController {
    private let viewModel: SocketListViewModel
    private let store: SocketStore

    private let archive: SessionArchive?

    /// `previousSessionTitle` makes this a read-only view of a saved session.
    init(
        viewModel: SocketListViewModel,
        store: SocketStore,
        archive: SessionArchive? = nil,
        previousSessionTitle: String? = nil
    ) {
        self.viewModel = viewModel
        self.store = store
        self.archive = previousSessionTitle == nil ? archive : nil
        super.init(style: .insetGrouped)
        title = previousSessionTitle ?? "Sockets"
        // The tabs belong to the live session, so they'd be misleading over a saved one.
        hidesBottomBarWhenPushed = previousSessionTitle != nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SocketListViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        DashboardTheme.style(tableView)
        tableView.register(TrafficRowCell.self, forCellReuseIdentifier: TrafficRowCell.reuseIdentifier)
        navigationItem.rightBarButtonItem = archive.map { archive in
            PreviousSessions.button(archive: archive) { [weak self] session in
                let list = SocketListViewController(
                    viewModel: SocketListViewModel(store: session.socketStore),
                    store: session.socketStore,
                    previousSessionTitle: PreviousSessions.title(for: session)
                )
                self?.navigationController?.pushViewController(list, animated: true)
            }
        }
        viewModel.onChange = { [weak self] in self?.tableView.reloadData() }
        viewModel.startObserving()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: TrafficRowCell.reuseIdentifier, for: indexPath)
        let row = viewModel.rows[indexPath.row]
        (cell as? TrafficRowCell)?.show(
            tag: row.tag,
            title: row.name,
            detail: row.detail,
            status: row.status,
            outcome: row.outcome
        )
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let connection = viewModel.connection(id: viewModel.rows[indexPath.row].id) else { return }
        let timeline = SocketTimelineViewController(
            viewModel: SocketTimelineViewModel(store: store, connection: connection)
        )
        navigationController?.pushViewController(timeline, animated: true)
    }
}
