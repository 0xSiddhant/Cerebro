import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// Picks where Copy to and Move to send items: a writable folder in the same root, one level per screen.
/// The items themselves aren't listed, so a folder can't be sent into itself.
final class FolderPickerViewController: UITableViewController {
    private static let cellIdentifier = "folder"

    private let root: FileRoot
    private let folder: URL
    private let excluded: Set<URL>
    private let confirmTitle: String
    private let onPick: @MainActor (URL) -> Void
    private var folders: [FileEntry] = []
    private lazy var confirmButton: UIBarButtonItem = {
        let button = UIBarButtonItem(title: confirmTitle, primaryAction: UIAction { [weak self] _ in self?.pick() })
        button.style = .done
        button.isEnabled = false
        return button
    }()

    /// `confirmTitle` names the action, such as "Move Here", and `onPick` receives the chosen folder.
    init(
        root: FileRoot,
        folder: URL,
        excluding excluded: Set<URL>,
        confirmTitle: String,
        onPick: @escaping @MainActor (URL) -> Void
    ) {
        self.root = root
        self.folder = folder
        self.excluded = excluded
        self.confirmTitle = confirmTitle
        self.onPick = onPick
        super.init(style: .insetGrouped)
        title = root.isRootFolder(folder) ? root.name : folder.lastPathComponent
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FolderPickerViewController is built in code")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) }
        )
        toolbarItems = [UIBarButtonItem(systemItem: .flexibleSpace), confirmButton]
        navigationController?.isToolbarHidden = false
        Task { await load() }
    }

    private func load() async {
        let (root, folder, excluded) = (root, folder, excluded)
        let (entries, isWritable) = await Task.detached(priority: .userInitiated) {
            let entries = (try? FolderListing.entries(in: folder, root: root)) ?? []
            let writable = entries.filter { $0.kind == .folder && $0.isWritable && !excluded.contains($0.url) }
            let isWritable = !root.isReadOnly && (try? FileEntry.read(folder).isWritable) == true
            return (FileSortOrder.name.sorted(writable), isWritable)
        }
        .value
        folders = entries
        confirmButton.isEnabled = isWritable
        tableView.reloadData()
    }

    private func pick() {
        let (folder, onPick) = (folder, onPick)
        dismiss(animated: true) { onPick(folder) }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        folders.count
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        folders.isEmpty ? "No folders here can take items." : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = folders[indexPath.row].name
        content.image = UIImage(systemName: "folder")
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let next = FolderPickerViewController(
            root: root,
            folder: folders[indexPath.row].url,
            excluding: excluded,
            confirmTitle: confirmTitle,
            onPick: onPick
        )
        navigationController?.pushViewController(next, animated: true)
    }
}
