import UIKit

/// The System Info tab: the network the device is on, connection quality, session totals and the
/// downloads still running.
final class SystemInfoViewController: UITableViewController {
    private static let cellIdentifier = "info"

    private let viewModel: SystemInfoViewModel

    init(viewModel: SystemInfoViewModel) {
        self.viewModel = viewModel
        super.init(style: .insetGrouped)
        title = "System Info"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SystemInfoViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        tableView.allowsSelection = false
        viewModel.onChange = { [weak self] in self?.tableView.reloadData() }
        viewModel.startObserving()
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        viewModel.sections[section].title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        viewModel.sections[section].footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        let row = viewModel.sections[indexPath.section].rows[indexPath.row]
        var content = UIListContentConfiguration.valueCell()
        content.text = row.title
        content.secondaryText = row.value
        content.secondaryTextProperties.font = .monospacedDigitSystemFont(ofSize: 15, weight: .regular)
        // An IPv6 address or a long host is wider than a phone.
        content.secondaryTextProperties.numberOfLines = 0
        cell.contentConfiguration = content
        return cell
    }
}
