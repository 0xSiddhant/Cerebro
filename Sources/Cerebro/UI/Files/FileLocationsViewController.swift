import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// The Files tab: the data container, the app bundle and any named App Group containers, each with what
/// it holds. Sizes are worked out while the screen is on, and leaving it cancels them.
final class FileLocationsViewController: UITableViewController {
    private static let cellIdentifier = "location"

    private let roots: [FileRoot]
    private let bodyLimit: Int
    private var sizes: [FileRoot: FolderMeasurement] = [:]
    private var measuring: [Task<Void, Never>] = []

    init(roots: [FileRoot], bodyLimit: Int) {
        self.roots = roots
        self.bodyLimit = bodyLimit
        super.init(style: .insetGrouped)
        title = "Files"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FileLocationsViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        measuring = roots.map { root in
            Task.detached(priority: .utility) { [weak self] in
                guard let size = try? FolderMeasurement.measure(root.url, root: root) else { return }
                await self?.show(size, for: root)
            }
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        measuring.forEach { $0.cancel() }
        measuring = []
    }

    private func show(_ size: FolderMeasurement, for root: FileRoot) {
        sizes[root] = size
        if let row = roots.firstIndex(of: root) {
            tableView.reconfigureRows(at: [IndexPath(row: row, section: 0)])
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        roots.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        "Files are shown exactly as they are on disk. Redaction rules don't apply to them."
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        let root = roots[indexPath.row]
        var content = UIListContentConfiguration.subtitleCell()
        content.image = UIImage(systemName: Self.symbol(for: root.kind))
        content.text = root.name
        let size = sizes[root].map(DisplayFormat.folderContents) ?? "…"
        content.secondaryText = root.isReadOnly ? "\(size) · Read-only" : size
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let root = roots[indexPath.row]
        let folder = FolderViewModel(root: root, folder: root.url, bodyLimit: bodyLimit)
        navigationController?.pushViewController(FolderViewController(viewModel: folder), animated: true)
    }

    private static func symbol(for kind: FileRoot.Kind) -> String {
        switch kind {
        case .dataContainer: return "internaldrive"
        case .appBundle: return "app"
        case .appGroup: return "square.stack.3d.up"
        }
    }
}
