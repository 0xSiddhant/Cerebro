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
        // Redact more than the default `Authorization` and cookie headers: `redaction` below shows how.
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

        // Redaction. Cerebro replaces a matching value with `[redacted]` before storing anything, so the
        // secret never reaches the store, the console, or Copy cURL and share. Run the Redaction sample in
        // this app and open its request in the dashboard to see these rules work.
        //
        // With no configuration, the `Authorization`, `Proxy-Authorization`, `Cookie` and `Set-Cookie`
        // headers are already redacted. Add rules for anything else sensitive:
        //
        // - `headers` for custom auth headers, such as an API key.
        // - `queryParameters` for secrets in URLs, including a socket's URL. The Query list shows
        //   `[redacted]`, and the URL itself shows it percent-encoded, as `%5Bredacted%5D`.
        // - `jsonKeys` for passwords, tokens or personal data in bodies.
        //
        // Names ignore case and must match in full. Header and JSON rules apply to requests and responses.
        // JSON keys match at any depth, and the whole value is replaced, even an object or an array.
        //
        // `jsonKeys` has a cost, so set it only when you need it. Cerebro then parses each JSON body at
        // capture, in the background, and stores it re-encoded, so key order and spacing can change. A body
        // counts as JSON if its content type says so or it starts with `{` or `[`. A JSON body that can't be
        // parsed, or that's over `bodyLimit`, shows as withheld and is never stored.
        //
        // Redaction doesn't cover:
        //
        // - The URL path or fragment. Keep secrets out of them.
        // - Non-JSON HTTP bodies, such as form-encoded or plain text. They're stored as sent, even when
        //   they contain a `jsonKeys` name.
        // - Places a rule doesn't look. A query value that a server echoes in a response body needs a
        //   `jsonKeys` entry too, and a secret inside a longer JSON string, or a URL in a `Location` header,
        //   is left alone.
        // - Socket frames, unless `jsonKeys` is set. Then a frame that starts with `{` or `[` is treated like
        //   a JSON body, and any other frame is stored as sent unless its text contains a key name anywhere.
        //   That withholds the whole frame, so a short key such as `id` can hide a lot. Bytes that aren't
        //   valid UTF-8 are stored as sent. Close reasons, errors and state text containing a key name
        //   become `[redacted]`.
        let redaction = RedactionRules(
            headers: ["X-Api-Key"],
            jsonKeys: ["password", "ssn"],
            queryParameters: ["token"]
        )

        // This app registers a protobuf rule so it exercises that path:
        let rule = ProtoRule(messageType: Google_Protobuf_Struct.self)
        Cerebro.start(CerebroConfiguration(consoleLevel: .summary, redaction: redaction).registering([rule]))
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
