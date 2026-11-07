import ObjectiveC
import UIKit

/// Spots shakes with no change to the app, by hooking `UIWindow`. A shake reaches the window unless
/// something earlier in the responder chain keeps it, which is why this can be turned off.
///
/// It replaces the method rather than exchanging it with a renamed one, because UIKit forwards a shake
/// up the responder chain under whatever selector it was called with. A renamed call crashes the app.
@MainActor
enum ShakeDetector {
    private typealias MotionEnded = @convention(c) (UIWindow, Selector, UIEvent.EventSubtype, UIEvent?) -> Void

    private static let selector = #selector(UIResponder.motionEnded(_:with:))

    private static var handler: (() -> Void)?
    private static var original: IMP?

    static func install(handler: @escaping () -> Void) {
        guard self.handler == nil, let inherited = class_getInstanceMethod(UIWindow.self, selector) else { return }
        self.handler = handler
        let implementation = method_getImplementation(inherited)
        original = implementation
        let forward = unsafeBitCast(implementation, to: MotionEnded.self)
        let selector = selector
        let hook: @convention(block) (UIWindow, UIEvent.EventSubtype, UIEvent?) -> Void = { window, motion, event in
            forward(window, selector, motion, event)
            if motion == .motionShake {
                MainActor.assumeIsolated { Self.handler?() }
            }
        }
        class_replaceMethod(
            UIWindow.self,
            selector,
            imp_implementationWithBlock(hook),
            method_getTypeEncoding(inherited)
        )
    }

    static func uninstall() {
        guard handler != nil, let original, let method = class_getInstanceMethod(UIWindow.self, selector) else {
            return
        }
        handler = nil
        method_setImplementation(method, original)
    }
}
