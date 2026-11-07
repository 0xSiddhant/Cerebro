import Testing
import UIKit
@testable import Cerebro

/// The next responder after a window, which is how UIKit passes a shake along.
private final class ChainEnd: UIResponder {
    var shakes = 0

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        shakes += 1
    }
}

private final class ChainedWindow: UIWindow {
    let chainEnd = ChainEnd()

    override var next: UIResponder? {
        chainEnd
    }
}

/// Hooks `UIWindow` for the whole process, so these run one at a time.
@Suite(.serialized)
@MainActor
struct ShakeDetectorTests {
    @Test func shakeRunsTheHandlerAndStillTravelsUpTheResponderChain() {
        var shakes = 0
        ShakeDetector.install { shakes += 1 }
        defer { ShakeDetector.uninstall() }
        let window = ChainedWindow()

        window.motionEnded(.motionShake, with: nil)

        #expect(shakes == 1)
        #expect(window.chainEnd.shakes == 1)
    }

    @Test func otherMotionIsPassedAlongWithoutRunningTheHandler() {
        var shakes = 0
        ShakeDetector.install { shakes += 1 }
        defer { ShakeDetector.uninstall() }
        let window = ChainedWindow()

        window.motionEnded(.none, with: nil)

        #expect(shakes == 0)
        #expect(window.chainEnd.shakes == 1)
    }

    @Test func uninstallStopsTheHandlerAndLeavesTheChainWorking() {
        var shakes = 0
        ShakeDetector.install { shakes += 1 }
        ShakeDetector.uninstall()
        let window = ChainedWindow()

        window.motionEnded(.motionShake, with: nil)

        #expect(shakes == 0)
        #expect(window.chainEnd.shakes == 1)
    }

    @Test func secondInstallKeepsTheFirstHandler() {
        var first = 0
        var second = 0
        ShakeDetector.install { first += 1 }
        ShakeDetector.install { second += 1 }
        defer { ShakeDetector.uninstall() }

        ChainedWindow().motionEnded(.motionShake, with: nil)

        #expect(first == 1)
        #expect(second == 0)
    }
}
