import UIKit

/// An item's Info page. Tap a row to copy its value.
final class FileInfoViewController: UITableViewController {
    private static let cellIdentifier = "info"

    private let viewModel: FileInfoViewModel

    init(viewModel: FileInfoViewModel) {
        self.viewModel = viewModel
        super.init(style: .insetGrouped)
        title = "Info"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FileInfoViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        viewModel.onChange = { [weak self] in self?.tableView.reloadData() }
        Task { await viewModel.load() }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        let row = viewModel.rows[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.text = row.title
        content.textProperties.font = .preferredFont(forTextStyle: .footnote)
        content.textProperties.color = .secondaryLabel
        content.secondaryText = row.value
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .body)
        content.secondaryTextProperties.color = .label
        content.textToSecondaryTextVerticalPadding = 4
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = viewModel.rows[indexPath.row]
        UIPasteboard.general.string = row.value
        DashboardToast.show("Copied \(row.title.lowercased()).", in: navigationController?.view ?? view)
    }
}
