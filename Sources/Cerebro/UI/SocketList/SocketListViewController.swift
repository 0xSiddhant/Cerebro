import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// The Sockets tab: every captured socket, newest first.
final class SocketListViewController: UITableViewController {
    private let viewModel: SocketListViewModel
    private let store: SocketStore

    init(viewModel: SocketListViewModel, store: SocketStore) {
        self.viewModel = viewModel
        self.store = store
        super.init(style: .plain)
        title = "Sockets"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SocketListViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(TrafficRowCell.self, forCellReuseIdentifier: TrafficRowCell.reuseIdentifier)
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
