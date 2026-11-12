import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// Everything Cerebro knows about one request, split into pages so each one fits about one screen.
final class LogInspectorViewController: UITableViewController {
    private static let bodyCellIdentifier = "InspectorBodyCell"
    private static let headerIdentifier = "InspectorHeader"

    private let viewModel: LogInspectorViewModel
    private let tabs = UISegmentedControl(items: InspectorTab.allCases.map(\.title))
    private var selectedTab = InspectorTab.response
    private var sections: [InspectorSection] = []
    private var expandedRows = Set<IndexPath>()
    private var shownSummary: InspectorSummary?
    private lazy var copyCurlButton: UIButton = {
        var configuration = Self.actionButtonConfiguration(image: "doc.on.doc")
        configuration.title = "Copy cURL"
        configuration.imagePadding = 4
        return UIButton(
            configuration: configuration,
            primaryAction: UIAction { [weak self] _ in self?.copyCurl() }
        )
    }()
    private lazy var shareCurlButton: UIButton = {
        let button = UIButton(configuration: Self.actionButtonConfiguration(image: "square.and.arrow.up"))
        let transaction: @MainActor () -> HTTPTransaction = { [viewModel] in viewModel.transaction }
        button.menu = UIMenu(
            children: CurlActions.shareActions(for: viewModel.request, from: self) { [weak button] in button }
                + ExportActions.jsonActions(for: transaction, from: self) { [weak button] in button }
        )
        button.showsMenuAsPrimaryAction = true
        button.accessibilityLabel = "Share"
        return button
    }()

    init(viewModel: LogInspectorViewModel) {
        self.viewModel = viewModel
        super.init(style: .insetGrouped)
        title = viewModel.title
        // The floating tab bar would otherwise cover the bottom of the page.
        hidesBottomBarWhenPushed = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LogInspectorViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(InspectorFieldCell.self, forCellReuseIdentifier: InspectorFieldCell.reuseIdentifier)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.bodyCellIdentifier)
        tableView.register(UITableViewHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: Self.headerIdentifier)
        tableView.sectionHeaderTopPadding = 0
        tableView.sectionFooterHeight = 6
        showSummary()

        tabs.selectedSegmentIndex = selectedTab.rawValue
        tabs.addAction(UIAction { [weak self] _ in self?.showSelectedTab() }, for: .valueChanged)
        navigationItem.titleView = tabs
        sections = viewModel.sections(for: selectedTab)
        viewModel.onChange = { [weak self] in self?.showChanges() }
        viewModel.startObserving()
    }

    private func showSummary() {
        tableView.tableHeaderView = InspectorSummaryView(
            summary: viewModel.summary,
            actions: [copyCurlButton, shareCurlButton]
        )
        shownSummary = viewModel.summary
    }

    /// An open event stream got more events or ended. Only what changed is redrawn, so a page that
    /// didn't change stays still, and so do the summary's buttons.
    private func showChanges() {
        if viewModel.summary != shownSummary {
            (tableView.tableHeaderView as? InspectorSummaryView)?.show(viewModel.summary)
            shownSummary = viewModel.summary
            view.setNeedsLayout()
        }
        let updated = viewModel.sections(for: selectedTab)
        guard updated != sections else { return }
        let previous = sections
        sections = updated
        guard updated.count == previous.count else {
            expandedRows.removeAll()
            tableView.reloadData()
            return
        }
        // Usually just the events, which are the last section, so the rows above keep their places.
        let changed = IndexSet(updated.indices.filter { updated[$0] != previous[$0] })
        UIView.performWithoutAnimation { tableView.reloadSections(changed, with: .none) }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeSummaryToFit()
    }

    /// A table doesn't size its header view, so it needs its height set once its width is known.
    private func sizeSummaryToFit() {
        guard let summary = tableView.tableHeaderView else { return }
        let height = summary.systemLayoutSizeFitting(
            CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height
        guard summary.frame.height != height else { return }
        summary.frame.size.height = height
        tableView.tableHeaderView = summary
    }

    private func showSelectedTab() {
        selectedTab = InspectorTab(rawValue: tabs.selectedSegmentIndex) ?? .response
        sections = viewModel.sections(for: selectedTab)
        expandedRows.removeAll()
        tableView.reloadData()
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
    }

    private func row(at indexPath: IndexPath) -> InspectorRow {
        sections[indexPath.section].rows[indexPath.row]
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].rows.count
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: Self.headerIdentifier)
        var content = UIListContentConfiguration.groupedHeader()
        content.text = sections[section].title
        content.textProperties.font = .preferredFont(forTextStyle: .footnote).withBoldTraits()
        content.textProperties.color = .secondaryLabel
        content.directionalLayoutMargins.top = 8
        content.directionalLayoutMargins.bottom = 4
        header?.contentConfiguration = content
        return header
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let row = row(at: indexPath)
        if row.isBodyRow {
            return bodyCell(for: row, at: indexPath)
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: InspectorFieldCell.reuseIdentifier, for: indexPath)
        (cell as? InspectorFieldCell)?.show(row, isExpanded: expandedRows.contains(indexPath))
        return cell
    }

    private func bodyCell(for row: InspectorRow, at indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.bodyCellIdentifier, for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        content.text = "\(row.title) · \(row.value)"
        content.textProperties.font = .preferredFont(forTextStyle: .subheadline)
        content.secondaryText = row.preview
        content.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 4
        content.textToSecondaryTextVerticalPadding = 6
        cell.contentConfiguration = content
        cell.accessoryType = row.body == nil ? .none : .disclosureIndicator
        cell.selectionStyle = row.body == nil ? .none : .default
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = row(at: indexPath)
        if let body = row.body {
            let title = row.bodyTitle ?? "\(selectedTab.title) body"
            let viewer = BodyViewerViewController(viewModel: BodyViewerViewModel(title: title, body: body))
            navigationController?.pushViewController(viewer, animated: true)
        } else if !row.isBodyRow {
            toggleExpansion(of: indexPath)
        }
    }

    private func toggleExpansion(of indexPath: IndexPath) {
        if expandedRows.remove(indexPath) == nil {
            expandedRows.insert(indexPath)
        }
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }

    override func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        let row = row(at: indexPath)
        guard !row.isBodyRow else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Copy Value", image: UIImage(systemName: "doc.on.doc")) { _ in
                    self?.copy(row.value)
                },
                UIAction(title: "Copy Name and Value", image: UIImage(systemName: "text.badge.plus")) { _ in
                    self?.copy("\(row.title): \(row.value)")
                },
            ])
        })
    }

    private static func actionButtonConfiguration(image: String) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.tinted()
        configuration.image = UIImage(systemName: image)
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .caption1)
        configuration.buttonSize = .small
        configuration.cornerStyle = .capsule
        return configuration
    }

    private func copyCurl() {
        CurlActions.copy(viewModel.request, confirmingIn: navigationController?.view ?? view)
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        DashboardToast.show("Copied.", in: navigationController?.view ?? view)
    }
}

extension UIFont {
    fileprivate func withBoldTraits() -> UIFont {
        fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: 0) } ?? self
    }
}
