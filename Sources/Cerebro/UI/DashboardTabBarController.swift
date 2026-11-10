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
}

/// The dashboard's shell.
final class DashboardTabBarController: UITabBarController {
    private let onClose: () -> Void

    init(sources: DashboardSources, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
        let (store, socketStore, decoders) = (sources.store, sources.socketStore, sources.decoders)
        var tabs = [
            makeTab(
                root: HTTPListViewController(viewModel: HTTPListViewModel(store: store)),
                title: "HTTP",
                image: "network"
            ),
            makeTab(
                root: SocketListViewController(viewModel: SocketListViewModel(store: socketStore), store: socketStore),
                title: "Sockets",
                image: "bolt.horizontal"
            ),
        ]
        if ProtoConfigViewModel.hasMappings(in: decoders) {
            let viewModel = ProtoConfigViewModel(decoders: decoders, store: store, socketStore: socketStore)
            tabs.append(
                makeTab(
                    root: ProtoConfigViewController(viewModel: viewModel), title: "Proto Config", image: "curlybraces")
            )
        }
        tabs.append(
            makeTab(
                root: SystemInfoViewController(viewModel: SystemInfoViewModel(sources: sources)),
                title: "System Info",
                image: "info.circle"
            )
        )
        viewControllers = tabs
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DashboardTabBarController is built in code")
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
