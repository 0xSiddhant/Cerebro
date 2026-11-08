import UIKit

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// The dashboard's shell. PLAN-02 to PLAN-04 add the Sockets, Proto Config and System Info tabs.
final class DashboardTabBarController: UITabBarController {
    private let onClose: () -> Void

    init(store: TransactionStore, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
        let list = HTTPListViewController(viewModel: HTTPListViewModel(store: store))
        list.navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.close() }
        )
        let tab = UINavigationController(rootViewController: list)
        tab.tabBarItem = UITabBarItem(title: "HTTP", image: UIImage(systemName: "network"), tag: 0)
        viewControllers = [tab]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("DashboardTabBarController is built in code")
    }

    private func close() {
        dismiss(animated: true) { [onClose] in onClose() }
    }
}
