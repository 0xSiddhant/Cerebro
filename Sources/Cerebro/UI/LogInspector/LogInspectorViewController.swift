import UIKit

/// Everything Cerebro knows about one request.
final class LogInspectorViewController: UITableViewController {
    private static let cellIdentifier = "InspectorCell"

    private let viewModel: LogInspectorViewModel

    init(viewModel: LogInspectorViewModel) {
        self.viewModel = viewModel
        super.init(style: .insetGrouped)
        title = viewModel.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LogInspectorViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.sections.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        viewModel.sections[section].title
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        viewModel.sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = viewModel.sections[indexPath.section].rows[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = row.title
        content.textProperties.font = .preferredFont(forTextStyle: .caption1)
        content.textProperties.color = .secondaryLabel
        content.secondaryText = row.value
        content.secondaryTextProperties.font = .preferredFont(forTextStyle: .subheadline)
        content.secondaryTextProperties.color = .label
        cell.contentConfiguration = content
        cell.accessoryType = row.body == nil ? .none : .disclosureIndicator
        cell.selectionStyle = row.body == nil ? .none : .default
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let section = viewModel.sections[indexPath.section]
        guard let body = section.rows[indexPath.row].body else { return }
        let viewer = BodyViewerViewController(viewModel: BodyViewerViewModel(title: section.title, body: body))
        navigationController?.pushViewController(viewer, animated: true)
    }
}
