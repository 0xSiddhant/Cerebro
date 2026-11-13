import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// Everything the dashboard reads from, which capture owns.
struct DashboardSources {
    let store: TransactionStore
    let socketStore: SocketStore
    let decoders: [any BodyDecoder]
    let systemInfo: SystemInfoMonitor
    let downloads: DownloadProgressStore

    /// The sessions kept on disk, or `nil` if persistence is off.
    let archive: SessionArchive?

    /// The most bytes the Files tab reads of a file for the Body Viewer.
    let bodyLimit: Int

    /// The data container, the app bundle and the named App Group containers that exist, worked out off
    /// the main thread once Cerebro starts. `nil` while the Files tab is off, which leaves it out.
    let fileRoots: Task<[FileRoot], Never>?
}

/// The dashboard's tabs, in the order the bar shows them. An iPhone shows five before it adds More.
enum DashboardTab: Equatable {
    case http
    case sockets
    case protoConfig
    case files
    case systemInfo

    /// Proto Config only shows with rules to list, and Files only while it's on.
    static func visible(hasProtoMappings: Bool, isFileBrowserEnabled: Bool) -> [Self] {
        [.http, .sockets]
            + (hasProtoMappings ? [.protoConfig] : [])
            + (isFileBrowserEnabled ? [.files] : [])
            + [.systemInfo]
    }
}

/// The dashboard's shell.
final class DashboardTabBarController: UITabBarController {
    private let onClose: () -> Void

    init(sources: DashboardSources, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
        let tabs = DashboardTab.visible(
            hasProtoMappings: ProtoConfigViewModel.hasMappings(in: sources.decoders),
            isFileBrowserEnabled: sources.fileRoots != nil
        )
        viewControllers = tabs.map { makeTab($0, sources: sources) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DashboardTabBarController is built in code")
    }

    private func makeTab(_ tab: DashboardTab, sources: DashboardSources) -> UINavigationController {
        let (store, socketStore, decoders) = (sources.store, sources.socketStore, sources.decoders)
        switch tab {
        case .http:
            return makeTab(
                root: HTTPListViewController(viewModel: HTTPListViewModel(store: store), archive: sources.archive),
                title: "HTTP",
                image: "network"
            )
        case .sockets:
            return makeTab(
                root: SocketListViewController(
                    viewModel: SocketListViewModel(store: socketStore), store: socketStore, archive: sources.archive),
                title: "Sockets",
                image: "bolt.horizontal"
            )
        case .protoConfig:
            let viewModel = ProtoConfigViewModel(decoders: decoders, store: store, socketStore: socketStore)
            return makeTab(
                root: ProtoConfigViewController(viewModel: viewModel), title: "Proto Config", image: "curlybraces")
        case .files:
            return makeTab(
                root: FileLocationsViewController(roots: sources.fileRoots, bodyLimit: sources.bodyLimit),
                title: "Files",
                image: "folder"
            )
        case .systemInfo:
            return makeTab(
                root: SystemInfoViewController(viewModel: SystemInfoViewModel(sources: sources)),
                title: "System Info",
                image: "info.circle"
            )
        }
    }

    private func makeTab(root: UIViewController, title: String, image: String) -> UINavigationController {
        root.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.close() }
        )
        let tab = UINavigationController(rootViewController: root)
        tab.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: image), tag: 0)
        return tab
    }

    private func close() {
        dismiss(animated: true) { [onClose] in onClose() }
    }
}
