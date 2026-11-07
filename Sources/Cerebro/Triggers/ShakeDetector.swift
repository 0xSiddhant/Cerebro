import ObjectiveC
import UIKit

/// Spots shakes with no change to the app, by hooking `UIWindow`. A shake reaches the window unless
/// something earlier in the responder chain keeps it, which is why this can be turned off.
@MainActor
enum ShakeDetector {
    private static let original = #selector(UIResponder.motionEnded(_:with:))
    private static let replacement = #selector(UIWindow.cerebroMotionEnded(_:with:))

    fileprivate static var handler: (() -> Void)?

    static func install(handler: @escaping () -> Void) {
        guard self.handler == nil else { return }
        self.handler = handler
        exchange()
    }

    static func uninstall() {
        guard handler != nil else { return }
        handler = nil
        exchange()
    }

    private static func exchange() {
        guard let inherited = class_getInstanceMethod(UIWindow.self, original),
            let hook = class_getInstanceMethod(UIWindow.self, replacement)
        else { return }
        // Gives UIWindow its own copy if it only inherits one, so UIResponder itself stays untouched.
        class_addMethod(
            UIWindow.self,
            original,
            method_getImplementation(inherited),
            method_getTypeEncoding(inherited)
        )
        guard let own = class_getInstanceMethod(UIWindow.self, original) else { return }
        method_exchangeImplementations(own, hook)
    }
}

extension UIWindow {
    @objc fileprivate func cerebroMotionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        // While exchanged, this name points at the original, so this doesn't recurse.
        cerebroMotionEnded(motion, with: event)
        if motion == .motionShake {
            ShakeDetector.handler?()
        }
    }
}
