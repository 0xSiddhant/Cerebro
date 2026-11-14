import UIKit

/// Cerebro's own window. A touch that lands on nothing of ours falls through to the app.
final class PassthroughWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let hit = super.hitTest(point, with: event), let root = rootViewController?.view else { return nil }
        return hit === root ? nil : hit
    }
}
