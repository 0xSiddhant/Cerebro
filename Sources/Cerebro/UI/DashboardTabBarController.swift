import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// The dashboard's shell. PLAN-03 and PLAN-04 add the Proto Config and System Info tabs.
final class DashboardTabBarController: UITabBarController {
    private let onClose: () -> Void

    init(store: TransactionStore, socketStore: SocketStore, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
        viewControllers = [
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
