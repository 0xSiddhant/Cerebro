import UIKit

/// The root of Cerebro's window. It holds the trigger, and follows the app on orientation and status bar,
/// because the topmost window otherwise decides both.
final class OverlayViewController: UIViewController {
    let trigger = FloatingTriggerView()

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        hostViewController?.supportedInterfaceOrientations ?? .all
    }

    override var prefersStatusBarHidden: Bool {
        hostViewController?.prefersStatusBarHidden ?? false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        hostViewController?.preferredStatusBarStyle ?? .default
    }

    private var hostViewController: UIViewController? {
        view.window?.windowScene?.windows.first { !($0 is PassthroughWindow) }?.rootViewController
    }

    override func loadView() {
        view = UIView()
        view.backgroundColor = .clear
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(trigger)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        trigger.settle(in: view.bounds.inset(by: view.safeAreaInsets))
    }
}
