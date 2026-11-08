// To keep Cerebro out of Release builds' code, guard the import here and the start call below:
//
//     #if DEBUG
//     import Cerebro
//     #endif
//
// Use `#if canImport(Cerebro)` instead if only some configurations link it, for example with
// `pod 'Cerebro', :git => '...', :tag => 'v1.2.4', :configurations => ['Debug']`.
//
// This is optional. Cerebro already turns itself off in Ad Hoc, TestFlight and App Store builds.
import Cerebro
import CerebroProto
import SwiftProtobuf
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Ways to start Cerebro. Use one call, wrapped like this if you guarded the import above:
        //
        //     #if DEBUG
        //     Cerebro.start()
        //     #endif
        //
        // Default, which is all most apps need:
        //
        //     Cerebro.start()
        //
        // With protobuf rules. Decoding arrives in a later release. Add `import CerebroProto`, except with
        // CocoaPods, where `ProtoRule` comes from `import Cerebro`:
        //
        //     let rule = ProtoRule(messageType: MyResponse.self)
        //     Cerebro.start(CerebroConfiguration().registering([rule]))
        //
        // HTTP only, or WebSockets only: there's no setting for either. `Cerebro.start()` captures both.
        // `NWConnection` traffic needs `MonitoredNWConnection`, as `NWConnectionExchange` shows, and other
        // socket engines need `ExternalNetworkBridge`, as `TrafficSample` shows.
        //
        // How much each request prints to the console: `.off`, `.summary` (the default) or `.full`:
        //
        //     Cerebro.start(CerebroConfiguration(consoleLevel: .full))
        //
        // Keep fewer requests, or store less of each body (the defaults are 500 and 1 MB):
        //
        //     Cerebro.start(CerebroConfiguration(requestLimit: 100, bodyLimit: 256 * 1024))
        //
        // Keep fewer frames for each socket (the default is 1,000):
        //
        //     Cerebro.start(CerebroConfiguration(socketFrameLimit: 200))
        //
        // Redact more than the default `Authorization` and cookie headers:
        //
        //     let redaction = RedactionRules(
        //         headers: ["X-Api-Key"],
        //         jsonKeys: ["password"],
        //         queryParameters: ["token"]
        //     )
        //     Cerebro.start(CerebroConfiguration(redaction: redaction))
        //
        // Stop a shake from showing and hiding the floating button:
        //
        //     Cerebro.start(CerebroConfiguration(isShakeGestureEnabled: false))
        //
        // Also capture in Ad Hoc and TestFlight builds:
        //
        //     Cerebro.start(CerebroConfiguration(allowsDistributionBuilds: true))
        //
        // Options combine in one configuration:
        //
        //     Cerebro.start(CerebroConfiguration(consoleLevel: .off, requestLimit: 100))
        //
        // This app registers a protobuf rule so it exercises that path:
        let rule = ProtoRule(messageType: Google_Protobuf_Struct.self)
        Cerebro.start(CerebroConfiguration(consoleLevel: .summary).registering([rule]))
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
