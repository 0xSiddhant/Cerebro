import UIKit

/// The Proto Config tab: each rule, what it maps to, where it came from and how often it has matched.
final class ProtoConfigViewController: UITableViewController {
    private static let cellIdentifier = "rule"

    private let viewModel: ProtoConfigViewModel

    init(viewModel: ProtoConfigViewModel) {
        self.viewModel = viewModel
        super.init(style: .plain)
        title = "Proto Config"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ProtoConfigViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        DashboardTheme.style(tableView)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        tableView.allowsSelection = false
        viewModel.onChange = { [weak self] in self?.tableView.reloadData() }
        viewModel.startObserving()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.refresh()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        let row = viewModel.rows[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = row.title
        content.textProperties.font = .preferredFont(forTextStyle: .headline)
        content.secondaryText = "\(row.mapping)\n\(row.detail)"
        content.secondaryTextProperties.color = DashboardTheme.secondaryText
        content.secondaryTextProperties.numberOfLines = 0
        content.textToSecondaryTextVerticalPadding = 4
        cell.contentConfiguration = content
        return cell
    }
}
