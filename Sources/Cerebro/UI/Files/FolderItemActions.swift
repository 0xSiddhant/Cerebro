import UIKit
import UniformTypeIdentifiers

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// What a folder screen does with its items: the context menu, swipes, and each action's questions.
/// Every change runs off the main thread, and a failure shows the system's reason.
extension FolderViewController {
    override func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isEditing, let entry = entry(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            self?.menu(for: entry, anchor: { [weak tableView] in tableView?.cellForRow(at: indexPath) })
        })
    }

    override func tableView(
        _ tableView: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let entry = entry(at: indexPath) else { return nil }
        let actions = viewModel.actions(for: entry)
        var swipes: [UIContextualAction] = []
        if actions.contains(.delete) {
            let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, finished in
                self?.confirmDelete([entry])
                finished(false)
            }
            delete.image = UIImage(systemName: "trash")
            swipes.append(delete)
        }
        if actions.contains(.share) {
            let share = UIContextualAction(style: .normal, title: "Share") { [weak self] _, _, finished in
                self?.share([entry], anchor: tableView.cellForRow(at: indexPath) ?? tableView)
                finished(true)
            }
            share.image = UIImage(systemName: "square.and.arrow.up")
            share.backgroundColor = DashboardTheme.accentFill
            swipes.append(share)
        }
        return UISwipeActionsConfiguration(actions: swipes)
    }

    override func tableView(
        _ tableView: UITableView,
        leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let entry = entry(at: indexPath) else { return nil }
        let info = UIContextualAction(style: .normal, title: "Info") { [weak self] _, _, finished in
            self?.showInfo(entry)
            finished(true)
        }
        info.image = UIImage(systemName: "info.circle")
        info.backgroundColor = DashboardTheme.neutral
        return UISwipeActionsConfiguration(actions: [info])
    }

    // MARK: - Menu

    /// Only the actions that apply, grouped: preview, about, change, then delete.
    private func menu(
        for entry: FileEntry,
        anchor: @escaping @MainActor () -> (any UIPopoverPresentationControllerSourceItem)?
    ) -> UIMenu {
        let available = Set(viewModel.actions(for: entry))
        let groups: [[FileAction]] = [
            [.quickLook, .openAsText], [.info, .copyPath, .share], [.rename, .duplicate, .copyTo, .moveTo],
            [.deleteContents, .delete],
        ]
        let sections = groups.map { group in
            group.filter(available.contains).map { menuElement(for: $0, entry: entry, anchor: anchor) }
        }
        return UIMenu(children: sections.filter { !$0.isEmpty }.map { UIMenu(options: .displayInline, children: $0) })
    }

    private func menuElement(
        for action: FileAction,
        entry: FileEntry,
        anchor: @escaping @MainActor () -> (any UIPopoverPresentationControllerSourceItem)?
    ) -> UIMenuElement {
        if action == .copyPath {
            return copyPathMenu(for: entry)
        }
        return UIAction(
            title: action.title,
            image: UIImage(systemName: action.symbol),
            attributes: action.isDestructive ? .destructive : []
        ) { [weak self] _ in
            self?.perform(action, on: entry, anchor: anchor)
        }
    }

    private func perform(
        _ action: FileAction,
        on entry: FileEntry,
        anchor: @MainActor () -> (any UIPopoverPresentationControllerSourceItem)?
    ) {
        switch action {
        case .quickLook: showQuickLook(entry.url)
        case .openAsText: showBody(of: entry.url, asRaw: true)
        case .info: showInfo(entry)
        case .share: share([entry], anchor: anchor() ?? tableView)
        case .rename: rename(entry)
        case .duplicate: run { try $0.duplicate(entry.url) }
        case .copyTo, .moveTo: chooseDestination(for: [entry], moving: action == .moveTo)
        case .deleteContents: confirmDeleteContents(of: entry)
        case .delete: confirmDelete([entry])
        case .copyPath: break
        }
    }

    private func copyPathMenu(for entry: FileEntry) -> UIMenu {
        let root = viewModel.root
        let paths = [
            ("Full Path", entry.url.path),
            ("Path in \(root.name)", root.relativePath(of: entry.url) ?? entry.name),
        ]
        return UIMenu(
            title: FileAction.copyPath.title,
            image: UIImage(systemName: FileAction.copyPath.symbol),
            children: paths.map { name, path in
                UIAction(title: name, subtitle: path) { [weak self] _ in
                    UIPasteboard.general.string = path
                    guard let self else { return }
                    DashboardToast.show("Copied the path.", in: navigationController?.view ?? view)
                }
            }
        )
    }

    // MARK: - Actions

    /// Runs a change off the main thread, and shows the system's reason if it fails.
    private func run(_ operation: @escaping @Sendable (FileOperations) throws -> Void) {
        Task {
            do {
                try await viewModel.perform(operation)
            } catch {
                FileAlerts.showFailure(error, from: self)
            }
        }
    }

    private func showInfo(_ entry: FileEntry) {
        let info = FileInfoViewController(viewModel: FileInfoViewModel(entry: entry, root: viewModel.root))
        navigationController?.pushViewController(info, animated: true)
    }

    private func rename(_ entry: FileEntry) {
        let rename: @MainActor (String) -> Void = { [weak self] name in
            self?.run { try $0.rename(entry.url, to: name) }
        }
        FileAlerts.askForName(title: "Rename", initial: entry.name, confirm: "Rename", from: self, then: rename)
    }

    func createFolder() {
        let folder = viewModel.folder
        let create: @MainActor (String) -> Void = { [weak self] name in
            self?.run { try $0.createFolder(named: name, in: folder) }
        }
        FileAlerts.askForName(title: "New Folder", initial: "New Folder", confirm: "Create", from: self, then: create)
    }

    /// Picks a file with the system's document picker, to seed test data.
    func importFile() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.delegate = self
        present(picker, animated: true)
    }

    func share(_ entries: [FileEntry], anchor: any UIPopoverPresentationControllerSourceItem) {
        let root = viewModel.root
        CapturedContentSharing.shareFiles(from: self, anchor: anchor) {
            try FileSharePreparation.prepare(entries, root: root)
        }
    }

    /// Opens the folder picker at this folder, with the folders above it a tap away.
    func chooseDestination(for entries: [FileEntry], moving: Bool) {
        let root = viewModel.root
        let items = entries.map(\.url)
        let pick: @MainActor (URL) -> Void = { [weak self] destination in
            self?.setSelecting(false)
            self?.send(items, into: destination, moving: moving)
        }
        var folder = root.url
        var screens = [folder]
        for name in (root.relativePath(of: viewModel.folder) ?? "").split(separator: "/") {
            folder.appendPathComponent(String(name), isDirectory: true)
            screens.append(folder)
        }
        let navigation = DashboardNavigationController()
        navigation.viewControllers = screens.map { screen in
            FolderPickerViewController(
                root: root, folder: screen, excluding: Set(items), confirmTitle: moving ? "Move Here" : "Copy Here",
                onPick: pick)
        }
        present(navigation, animated: true)
    }

    private func send(_ items: [URL], into destination: URL, moving: Bool) {
        run { operations in
            _ = try moving ? operations.move(items, into: destination) : operations.copy(items, into: destination)
        }
    }

    func confirmDelete(_ entries: [FileEntry]) {
        let title = entries.count == 1 ? "Delete “\(entries[0].name)”?" : "Delete \(entries.count) items?"
        let delete: @MainActor () -> Void = { [weak self] in
            self?.setSelecting(false)
            self?.delete(entries.map(\.url))
        }
        Task {
            let message = await viewModel.deleteQuestion(for: entries)
            FileAlerts.confirmDestruction(title: title, message: message, confirm: "Delete", from: self, then: delete)
        }
    }

    private func delete(_ items: [URL]) {
        run { try $0.delete(items) }
    }

    private func confirmDeleteContents(of entry: FileEntry) {
        let empty: @MainActor () -> Void = { [weak self] in self?.deleteContents(of: entry.url) }
        Task {
            let message = await viewModel.deleteQuestion(for: [entry], contentsOnly: true)
            FileAlerts.confirmDestruction(
                title: "Delete everything in “\(entry.name)”?", message: message, confirm: "Delete Contents",
                from: self, then: empty)
        }
    }

    private func deleteContents(of folder: URL) {
        run { try $0.deleteContents(of: folder) }
    }
}

extension FolderViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let folder = viewModel.folder
        run { operations in
            for url in urls {
                try operations.importItem(at: url, into: folder)
            }
        }
    }
}
