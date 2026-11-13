import UIKit

/// The System Info tab, split into pages so each one fits about one screen: the network, the session's
/// traffic, and the app and device.
final class SystemInfoViewController: UITableViewController {
    private static let cellIdentifier = "info"
    private static let longValueLength = 28

    private let viewModel: SystemInfoViewModel
    private let tabs = UISegmentedControl(items: SystemInfoTab.allCases.map(\.title))
    private let summaryView = SystemInfoSummaryView()
    private var selectedTab = SystemInfoTab.network
    private var sections: [SystemInfoSection] = []

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
        tableView.tableHeaderView = summaryView
        tabs.selectedSegmentIndex = selectedTab.rawValue
        tabs.addAction(UIAction { [weak self] _ in self?.showSelectedTab() }, for: .valueChanged)
        navigationItem.titleView = tabs
        viewModel.onChange = { [weak self] in self?.reload() }
        viewModel.startObserving()
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeSummaryToFit()
    }

    private func showSelectedTab() {
        selectedTab = SystemInfoTab(rawValue: tabs.selectedSegmentIndex) ?? .network
        reload()
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
    }

    private func reload() {
        sections = viewModel.sections(for: selectedTab)
        summaryView.show(viewModel.summary)
        tableView.reloadData()
        view.setNeedsLayout()
    }

    /// A table doesn't size its header view, so it needs its height set once its width is known.
    private func sizeSummaryToFit() {
        let height = summaryView.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        guard summaryView.frame.height != height else { return }
        summaryView.frame.size.height = height
        tableView.tableHeaderView = summaryView
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        sections[section].footer
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        let row = sections[indexPath.section].rows[indexPath.row]
        var content = UIListContentConfiguration.valueCell()
        content.text = row.title
        content.secondaryText = row.value
        // An IPv6 address is 39 characters, which only fits one line of a phone at a smaller size.
        let isLong = row.value.split(separator: "\n").contains { $0.count > Self.longValueLength }
        content.secondaryTextProperties.font = .monospacedDigitSystemFont(ofSize: isLong ? 12 : 15, weight: .regular)
        content.secondaryTextProperties.numberOfLines = 0
        content.image = row.symbol.flatMap { UIImage(systemName: $0) }
        content.imageProperties.tintColor = DashboardTheme.secondaryText
        content.imageProperties.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .footnote)
        content.imageProperties.reservedLayoutSize = CGSize(width: 22, height: 0)
        cell.contentConfiguration = content
        return cell
    }

    /// A tap copies the value, which is what an address or a version is usually wanted for.
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = sections[indexPath.section].rows[indexPath.row]
        UIPasteboard.general.string = row.value
        DashboardToast.show("\(row.title) copied.", in: navigationController?.view ?? view)
    }
}
