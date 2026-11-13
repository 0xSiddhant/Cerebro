import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// The HTTP tab: every captured request, newest first, with search and filters.
final class HTTPListViewController: UITableViewController {
    private let viewModel: HTTPListViewModel
    private lazy var exportButton: UIBarButtonItem = {
        let export = UIAction(
            title: "Export Session as HAR",
            image: UIImage(systemName: "doc.zipper"),
            handler: { [weak self] _ in self?.exportSession() }
        )
        let button = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"), menu: UIMenu(children: [export]))
        button.accessibilityLabel = "Export"
        return button
    }()
    private lazy var clearButton: UIBarButtonItem = {
        let button = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            primaryAction: UIAction { [weak self] _ in self?.confirmClear() }
        )
        button.accessibilityLabel = "Clear requests"
        return button
    }()
    private lazy var dataSource = UITableViewDiffableDataSource<Int, UUID>(tableView: tableView) { [weak self] in
        self?.cell(in: $0, at: $1, for: $2)
    }

    private let archive: SessionArchive?
    private let previousSessionTitle: String?

    /// `previousSessionTitle` makes this a read-only view of a saved session, which can be exported but
    /// not cleared.
    init(viewModel: HTTPListViewModel, archive: SessionArchive? = nil, previousSessionTitle: String? = nil) {
        self.viewModel = viewModel
        self.archive = archive
        self.previousSessionTitle = previousSessionTitle
        super.init(style: .plain)
        title = previousSessionTitle ?? "HTTP"
        // The tabs belong to the live session, so they'd be misleading over a saved one.
        hidesBottomBarWhenPushed = previousSessionTitle != nil
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HTTPListViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(TrafficRowCell.self, forCellReuseIdentifier: TrafficRowCell.reuseIdentifier)
        tableView.dataSource = dataSource
        navigationItem.searchController = makeSearchController()
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.rightBarButtonItems = barButtons()
        viewModel.onChange = { [weak self] in self?.showRows() }
        viewModel.startObserving()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath), let inspector = viewModel.inspector(id: id)
        else { return }
        navigationController?.pushViewController(LogInspectorViewController(viewModel: inspector), animated: true)
    }

    override func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let request = request(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            guard let self else { return nil }
            let copy = UIAction(title: "Copy cURL", image: UIImage(systemName: "doc.on.doc")) { [weak self] _ in
                self?.copyCurl(of: request)
            }
            let share = CurlActions.shareActions(for: request, from: self) { [weak self] in
                self?.tableView.cellForRow(at: indexPath)
            }
            return UIMenu(children: [copy] + share)
        })
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let request = request(at: indexPath) else { return nil }
        let copy = UIContextualAction(style: .normal, title: "Copy cURL") { [weak self] _, _, finished in
            self?.copyCurl(of: request)
            finished(true)
        }
        copy.backgroundColor = DashboardTheme.accentFill
        copy.image = UIImage(systemName: "doc.on.doc")
        return UISwipeActionsConfiguration(actions: [copy])
    }

    private func request(at indexPath: IndexPath) -> CapturedRequest? {
        dataSource.itemIdentifier(for: indexPath).flatMap { viewModel.transaction(id: $0)?.request }
    }

    /// The whole session, not just the rows the search and filter leave on screen.
    private func exportSession() {
        Task { [weak self, viewModel] in
            let transactions = await viewModel.sessionTransactions()
            guard let self else { return }
            ExportActions.shareHAR(of: transactions, from: self, anchor: exportButton)
        }
    }

    private func barButtons() -> [UIBarButtonItem] {
        guard previousSessionTitle == nil else { return [exportButton] }
        let history = archive.map { archive in
            PreviousSessions.button(archive: archive) { [weak self] session in
                let list = HTTPListViewController(
                    viewModel: HTTPListViewModel(store: session.store),
                    previousSessionTitle: PreviousSessions.title(for: session)
                )
                self?.navigationController?.pushViewController(list, animated: true)
            }
        }
        return [exportButton, clearButton] + [history].compactMap { $0 }
    }

    /// Clearing can't be undone, so it asks first.
    private func confirmClear() {
        let alert = UIAlertController(
            title: "Clear all requests?",
            message: "This removes every captured HTTP request and resets the session totals. Sockets are kept.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(
            UIAlertAction(title: "Clear", style: .destructive) { [viewModel] _ in
                Task { await viewModel.clear() }
            }
        )
        present(alert, animated: true)
    }

    private func copyCurl(of request: CapturedRequest) {
        CurlActions.copy(request, confirmingIn: navigationController?.view ?? view)
    }

    private func cell(in table: UITableView, at indexPath: IndexPath, for id: UUID) -> UITableViewCell {
        let cell = table.dequeueReusableCell(withIdentifier: TrafficRowCell.reuseIdentifier, for: indexPath)
        if let row = viewModel.rows.first(where: { $0.id == id }) {
            (cell as? TrafficRowCell)?.show(
                tag: row.method,
                tagTint: DashboardTheme.method(row.method),
                marker: row.marker,
                title: row.path,
                detail: row.detail,
                status: row.status,
                outcome: row.outcome
            )
        }
        return cell
    }

    private func makeSearchController() -> UISearchController {
        let search = UISearchController(searchResultsController: nil)
        search.obscuresBackgroundDuringPresentation = false
        search.searchResultsUpdater = self
        search.searchBar.placeholder = "URL, method or status"
        search.searchBar.scopeButtonTitles = HTTPListFilter.allCases.map(\.title)
        search.searchBar.showsScopeBar = true
        search.searchBar.delegate = self
        return search
    }

    private func showRows() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>()
        snapshot.appendSections([0])
        snapshot.appendItems(viewModel.rows.map(\.id))
        // The snapshot only holds IDs, so a row whose ID is unchanged wouldn't redraw without this.
        snapshot.reconfigureItems(viewModel.changedRowIDs)
        dataSource.apply(snapshot, animatingDifferences: false)
    }
}

extension HTTPListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.searchText = searchController.searchBar.text ?? ""
    }
}

extension HTTPListViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        viewModel.filter = HTTPListFilter(rawValue: selectedScope) ?? .all
    }
}
