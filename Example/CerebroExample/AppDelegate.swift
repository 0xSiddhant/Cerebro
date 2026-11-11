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
        // With protobuf rules, in code, generated from `traffic_map.json`, or both. Add `import CerebroProto`,
        // except with CocoaPods, where `ProtoRule` comes from `import Cerebro`:
        //
        //     let rule = ProtoRule(match: .init(host: "api.example.com"), direction: .response, messageType: MyResponse.self)
        //     Cerebro.start(CerebroConfiguration().registering([rule] + ProtoRule.generated))
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
        // Redact credentials and personal data, which Cerebro doesn't do on its own: `redaction` below shows how.
        //
        // Show the device's public IP on the System Info tab. It's off by default, because it asks
        // `api.ipify.org`, which is the only data Cerebro sends off the device:
        //
        //     Cerebro.start(CerebroConfiguration(isPublicIPLookupEnabled: true))
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

        // Redaction. Cerebro redacts nothing until you choose. With no rules, `Authorization`, cookies and
        // every other value reach the dashboard, console, Copy cURL and share exactly as sent. A value your
        // rules select is replaced with `[redacted]` before anything is stored, so it never reaches any of
        // those. Run the Redaction sample in this app and open its request in the dashboard to see it work.
        //
        // - `sensitiveHeaders` selects common credential headers. Select the ones your app really sends:
        //   `.authorization` for bearer tokens and logins, `.proxyAuthorization` for a proxy that needs a
        //   login, `.cookie` and `.setCookie` for cookie sessions, `.apiKey`, `.xAPIKey` and `.xGoogAPIKey`
        //   for API keys, `.xAuthToken` and `.xAccessToken` for token headers, `.xCSRFToken` and
        //   `.xXSRFToken` for CSRF protection, and `.xAmzSecurityToken` for temporary AWS credentials.
        //   `Set(SensitiveHeader.allCases)` selects them all.
        // - `headers` for names the enum doesn't have, such as your app's own session header.
        // - `queryParameters` for secrets in URLs, including a socket's URL. The Query list shows
        //   `[redacted]`, and the URL itself shows it percent-encoded, as `%5Bredacted%5D`.
        // - `jsonKeys` for passwords, tokens or personal data in bodies and socket frames.
        //
        // Names ignore case and must match in full. Header and body rules apply to requests and responses.
        //
        // `jsonKeys` has a cost, so set it only when you need it. Cerebro then reads bodies at capture, in
        // the background. A body it can't redact shows as withheld and is never stored. Each kind differs:
        //
        // - JSON, meaning its content type says so or it starts with `{` or `[`. Keys match at any depth,
        //   and the whole value is replaced, even an object or an array. The body is stored re-encoded, so
        //   key order and spacing can change. One that can't be parsed or is over `bodyLimit` is withheld.
        // - Form-encoded HTTP bodies. Each named field's value is replaced, and the other fields keep their
        //   exact bytes. One over `bodyLimit` is withheld.
        // - Any other text, such as plain text, a form with no `Content-Type`, or a prefixed socket frame.
        //   It can't be redacted field by field, so it's withheld if it contains a key name anywhere. A
        //   short key such as `id` can hide a lot. Socket close reasons, errors and state text containing a
        //   key name become `[redacted]`.
        // - Binary, meaning bytes that aren't valid UTF-8, such as an image. It's stored as sent.
        //
        // Redaction doesn't cover:
        //
        // - The URL path or fragment. Keep secrets out of them.
        // - Any body or socket frame while `jsonKeys` is empty. They're stored as sent.
        // - Places a rule doesn't look. A query value that a server echoes in a response body needs a
        //   `jsonKeys` entry too, and a secret inside a longer JSON string, another form field's value, or
        //   a URL in a `Location` header is left alone.
        let redaction = RedactionRules(
            sensitiveHeaders: [.authorization, .proxyAuthorization, .cookie, .setCookie, .xAPIKey],
            headers: ["X-Cerebro-Example-Session"],
            jsonKeys: ["password", "ssn", "delete_token"],
            queryParameters: ["token"]
        )

        // A rule in code, for the "Protobuf: code rule" sample. Code rules are checked first. The
        // "Protobuf: traffic_map.json" sample is decoded by `ProtoRule.generated`, which this app's build
        // generates from `traffic_map.json` with the CerebroProtoPlugin build-tool plugin.
        let rule = ProtoRule(
            name: "Greeting",
            match: .init(host: "httpbin.org", path: "/post"),
            methods: ["POST"],
            direction: .request,
            messageType: Google_Protobuf_Struct.self
        )
        Cerebro.start(
            CerebroConfiguration(consoleLevel: .summary, redaction: redaction).registering([rule] + ProtoRule.generated)
        )
        // After `Cerebro.start()`, so a transfer that finished while the app wasn't running is captured.
        BackgroundTransfers.reconnect()
        return true
    }

    /// iOS calls this when it relaunches the app in the background to hand over finished transfers.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundTransfers.handleEvents(completionHandler: completionHandler)
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
