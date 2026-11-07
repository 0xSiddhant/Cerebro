import UIKit

/// The HTTP tab: every captured request, newest first, with search and filters.
final class HTTPListViewController: UITableViewController {
    private let viewModel: HTTPListViewModel
    private lazy var dataSource = UITableViewDiffableDataSource<Int, UUID>(tableView: tableView) { [weak self] in
        self?.cell(in: $0, at: $1, for: $2)
    }

    init(viewModel: HTTPListViewModel) {
        self.viewModel = viewModel
        super.init(style: .plain)
        title = "HTTP"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("HTTPListViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(HTTPTransactionCell.self, forCellReuseIdentifier: HTTPTransactionCell.reuseIdentifier)
        tableView.dataSource = dataSource
        navigationItem.searchController = makeSearchController()
        navigationItem.hidesSearchBarWhenScrolling = false
        viewModel.onChange = { [weak self] in self?.showRows() }
        viewModel.startObserving()
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath),
            let transaction = viewModel.transaction(id: id)
        else { return }
        let inspector = LogInspectorViewController(viewModel: LogInspectorViewModel(transaction: transaction))
        navigationController?.pushViewController(inspector, animated: true)
    }

    private func cell(in table: UITableView, at indexPath: IndexPath, for id: UUID) -> UITableViewCell {
        let cell = table.dequeueReusableCell(withIdentifier: HTTPTransactionCell.reuseIdentifier, for: indexPath)
        if let row = viewModel.rows.first(where: { $0.id == id }) {
            (cell as? HTTPTransactionCell)?.show(row)
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
