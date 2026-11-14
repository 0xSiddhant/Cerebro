import QuickLook
import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// One folder: its items with their size and date, a sort menu, search here or through subfolders, and
/// the path's parents in the title's menu. It reloads by itself when the app adds, removes or renames
/// an item, and pulling down also measures its folders again.
final class FolderViewController: UITableViewController {
    private static let cellIdentifier = "file"

    let viewModel: FolderViewModel

    private lazy var dataSource = UITableViewDiffableDataSource<Int, URL>(tableView: tableView) { [weak self] in
        self?.cell(in: $0, at: $1, for: $2)
    }
    private lazy var moreButton: UIBarButtonItem = {
        let button = UIBarButtonItem(image: UIImage(systemName: "ellipsis.circle"), menu: moreMenu())
        button.accessibilityLabel = "More"
        return button
    }()
    private lazy var doneButton = UIBarButtonItem(
        systemItem: .done,
        primaryAction: UIAction { [weak self] _ in self?.setSelecting(false) }
    )
    private lazy var selectionButtons: [FileAction: UIBarButtonItem] = [
        .share: selectionButton("square.and.arrow.up", label: "Share", action: .share),
        .copyTo: selectionButton("doc.on.doc", label: "Copy To", action: .copyTo),
        .moveTo: selectionButton("folder", label: "Move To", action: .moveTo),
        .delete: selectionButton("trash", label: "Delete", action: .delete),
    ]
    private let footer = UILabel()

    init(viewModel: FolderViewModel) {
        self.viewModel = viewModel
        super.init(style: .insetGrouped)
        title = viewModel.title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FolderViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        DashboardTheme.style(tableView)
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        tableView.dataSource = dataSource
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.tableFooterView = footer
        footer.font = .preferredFont(forTextStyle: .footnote)
        footer.textColor = DashboardTheme.secondaryText
        footer.textAlignment = .center
        footer.numberOfLines = 0
        navigationItem.searchController = makeSearchController()
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.rightBarButtonItems = [moreButton]
        navigationItem.titleMenuProvider = { [weak self] _ in self?.pathMenu() }
        refreshControl = UIRefreshControl(
            frame: .zero, primaryAction: UIAction { [weak self] _ in self?.pullToRefresh() })
        viewModel.onChange = { [weak self] in self?.showItems() }
        viewModel.onSizesChange = { [weak self] in self?.redraw($0) }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewModel.startWatching()
        Task { await viewModel.load() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isEditing {
            setSelecting(false)
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.stopWatching()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        sizeFooter()
    }

    // MARK: - Rows

    private func cell(in table: UITableView, at indexPath: IndexPath, for id: URL) -> UITableViewCell {
        let cell = table.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        // Here rather than when a row scrolls in, so a row redrawn after its size was reset is measured too.
        viewModel.measureIfNeeded(id)
        guard let row = viewModel.row(for: id) else { return cell }
        var content = UIListContentConfiguration.subtitleCell()
        content.image = UIImage(systemName: row.symbol)
        content.text = row.name
        content.secondaryText = row.detail
        content.secondaryTextProperties.color = DashboardTheme.secondaryText
        content.secondaryTextProperties.numberOfLines = 1
        cell.contentConfiguration = content
        cell.accessoryType = row.isFolder ? .disclosureIndicator : .none
        return cell
    }

    private func showItems() {
        var snapshot = NSDiffableDataSourceSnapshot<Int, URL>()
        snapshot.appendSections([0])
        snapshot.appendItems(viewModel.items)
        // The snapshot only holds paths, so a row whose size or date changed wouldn't redraw without this.
        snapshot.reconfigureItems(viewModel.changedItems)
        dataSource.apply(snapshot, animatingDifferences: false)
        footer.text = viewModel.notice
        sizeFooter()
        moreButton.menu = moreMenu()
        updateSelectionButtons()
    }

    private func redraw(_ ids: [URL]) {
        var snapshot = dataSource.snapshot()
        let present = ids.filter { snapshot.indexOfItem($0) != nil }
        guard !present.isEmpty else { return }
        snapshot.reconfigureItems(present)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func sizeFooter() {
        let width = tableView.bounds.width
        let fitting = footer.sizeThatFits(CGSize(width: width - 32, height: .greatestFiniteMagnitude))
        let height = footer.text == nil ? 0 : fitting.height + 32
        guard footer.frame.size != CGSize(width: width, height: height) else { return }
        footer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        tableView.tableFooterView = footer
    }

    private func pullToRefresh() {
        Task {
            await viewModel.load(resettingSizes: true)
            refreshControl?.endRefreshing()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard !isEditing else {
            updateSelectionButtons()
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        if let entry = entry(at: indexPath) {
            open(entry)
        }
    }

    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        updateSelectionButtons()
    }

    func entry(at indexPath: IndexPath) -> FileEntry? {
        dataSource.itemIdentifier(for: indexPath).flatMap(viewModel.entry(for:))
    }

    // MARK: - Opening

    private func open(_ entry: FileEntry) {
        switch viewModel.opening(for: entry) {
        case .folder(let url):
            showFolder(url)
        case .quickLook(let url):
            // Quick Look shows a blank icon for what it can't render, so those open as text or hex.
            if QLPreviewController.canPreview(url as NSURL) {
                showQuickLook(url)
            } else {
                showBody(of: url, asRaw: false)
            }
        case .bodyViewer(let url):
            showBody(of: url, asRaw: false)
        case .refused(let reason):
            DashboardToast.show(reason, in: navigationController?.view ?? view)
        }
    }

    func showQuickLook(_ file: URL) {
        navigationController?.pushViewController(FileQuickLookController(file: file), animated: true)
    }

    func showBody(of file: URL, asRaw: Bool) {
        Task {
            do {
                let body = try await viewModel.body(of: file, asRaw: asRaw)
                let viewer = BodyViewerViewModel(title: file.lastPathComponent, body: body, source: .file)
                navigationController?.pushViewController(BodyViewerViewController(viewModel: viewer), animated: true)
            } catch {
                FileAlerts.showFailure(error, from: self)
            }
        }
    }

    /// Opens a folder one level per screen, so Back always goes up one level, even from a search result
    /// several folders down.
    func showFolder(_ url: URL) {
        let root = viewModel.root
        let here = root.relativePath(of: viewModel.folder).map(Self.components) ?? []
        let there = root.relativePath(of: url).map(Self.components) ?? []
        var screens: [UIViewController] = []
        if there.count > here.count, there.starts(with: here) {
            var folder = viewModel.folder
            for name in there.dropFirst(here.count) {
                folder.appendPathComponent(name, isDirectory: true)
                screens.append(makeFolderScreen(folder))
            }
        } else {
            screens.append(makeFolderScreen(url))
        }
        guard let navigation = navigationController else { return }
        navigation.setViewControllers(navigation.viewControllers + screens, animated: true)
    }

    private static func components(_ path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    private func makeFolderScreen(_ folder: URL) -> FolderViewController {
        FolderViewController(
            viewModel: FolderViewModel(root: viewModel.root, folder: folder, bodyLimit: viewModel.bodyLimit))
    }

    /// The folders above this one, nearest first, back to the list of locations.
    private func pathMenu() -> UIMenu? {
        guard let stack = navigationController?.viewControllers, let index = stack.firstIndex(of: self), index > 0
        else { return nil }
        let parents = stack[..<index].reversed().map { screen in
            UIAction(
                title: screen.title ?? "",
                image: UIImage(systemName: screen is Self ? "folder" : "externaldrive")
            ) { [weak self] _ in
                self?.navigationController?.popToViewController(screen, animated: true)
            }
        }
        return UIMenu(children: parents)
    }
}

// MARK: - Bar buttons and selection

extension FolderViewController {
    private func moreMenu() -> UIMenu {
        var items: [UIMenuElement] = []
        if !viewModel.items.isEmpty {
            items.append(
                UIAction(title: "Select", image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
                    self?.setSelecting(true)
                })
        }
        if viewModel.isFolderWritable {
            items.append(
                UIAction(title: "New Folder", image: UIImage(systemName: "folder.badge.plus")) { [weak self] _ in
                    self?.createFolder()
                })
            items.append(
                UIAction(title: "Import File", image: UIImage(systemName: "square.and.arrow.down")) { [weak self] _ in
                    self?.importFile()
                })
        }
        let sorts = FileSortOrder.allCases.map { order in
            let state: UIMenuElement.State = order == viewModel.sortOrder ? .on : .off
            return UIAction(title: Self.title(of: order), state: state) { [weak self] _ in
                self?.viewModel.sortOrder = order
            }
        }
        items.append(UIMenu(title: "Sort By", options: .displayInline, children: sorts))
        return UIMenu(children: items)
    }

    private static func title(of order: FileSortOrder) -> String {
        switch order {
        case .name: return "Name"
        case .date: return "Date Modified"
        case .size: return "Size"
        }
    }

    func setSelecting(_ isSelecting: Bool) {
        setEditing(isSelecting, animated: true)
        navigationItem.rightBarButtonItems = [isSelecting ? doneButton : moreButton]
        let flexible = UIBarButtonItem.flexibleSpace()
        let buttons = [FileAction.share, .copyTo, .moveTo, .delete].compactMap { selectionButtons[$0] }
        toolbarItems = isSelecting ? Array(buttons.map { [$0, flexible] }.joined().dropLast()) : nil
        // On iOS 26 the tab bar floats over the toolbar, so it steps aside while items are selected.
        // Earlier designs place the toolbar above the tab bar. The floating bar needs an app built with
        // the iOS 26 SDK, which comes with Swift 6.2, and older compilers don't know `setTabBarHidden`.
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            tabBarController?.setTabBarHidden(isSelecting, animated: true)
        }
        #endif
        navigationController?.setToolbarHidden(!isSelecting, animated: true)
        updateSelectionButtons()
    }

    var selectedEntries: [FileEntry] {
        (tableView.indexPathsForSelectedRows ?? []).compactMap(entry(at:))
    }

    private func updateSelectionButtons() {
        guard isEditing else { return }
        let available = viewModel.selectionActions(for: selectedEntries.map(\.url))
        selectionButtons.forEach { action, button in button.isEnabled = available.contains(action) }
    }

    private func selectionButton(_ symbol: String, label: String, action: FileAction) -> UIBarButtonItem {
        let button = UIBarButtonItem(
            image: UIImage(systemName: symbol),
            primaryAction: UIAction { [weak self] _ in self?.performOnSelection(action) }
        )
        button.accessibilityLabel = label
        return button
    }

    private func performOnSelection(_ action: FileAction) {
        let entries = selectedEntries
        guard !entries.isEmpty else { return }
        switch action {
        case .share: share(entries, anchor: selectionButtons[.share] ?? moreButton)
        case .copyTo: chooseDestination(for: entries, moving: false)
        case .moveTo: chooseDestination(for: entries, moving: true)
        case .delete: confirmDelete(entries)
        default: break
        }
    }

    private func makeSearchController() -> UISearchController {
        let search = UISearchController(searchResultsController: nil)
        search.obscuresBackgroundDuringPresentation = false
        search.searchResultsUpdater = self
        search.searchBar.placeholder = "Name"
        search.searchBar.scopeButtonTitles = FileSearchScope.allCases.map(\.title)
        search.searchBar.delegate = self
        return search
    }
}

extension FolderViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        viewModel.searchText = searchController.searchBar.text ?? ""
    }
}

extension FolderViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        viewModel.searchScope = FileSearchScope(rawValue: selectedScope) ?? .thisFolder
    }
}
