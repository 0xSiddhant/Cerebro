# Cerebro

[![CI](https://github.com/0xSiddhant/Cerebro/actions/workflows/ci.yml/badge.svg?branch=develop)](https://github.com/0xSiddhant/Cerebro/actions/workflows/ci.yml)
[![Release](https://github.com/0xSiddhant/Cerebro/actions/workflows/release.yml/badge.svg)](https://github.com/0xSiddhant/Cerebro/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/0xSiddhant/Cerebro?sort=semver)](https://github.com/0xSiddhant/Cerebro/releases/latest)
[![License: MIT](https://img.shields.io/github/license/0xSiddhant/Cerebro)](LICENSE)
[![iOS 16+](https://img.shields.io/badge/iOS-16%2B-000000?logo=apple&logoColor=white)](#requirements)
[![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)](Package.swift)
[![SPM compatible](https://img.shields.io/badge/SPM-compatible-brightgreen)](#swift-package-manager)
[![CocoaPods via Git](https://img.shields.io/badge/CocoaPods-via%20Git-EE3322)](#cocoapods)

A debug-only network inspector for iOS apps. Cerebro captures HTTP, WebSocket and NWConnection traffic and shows it in a dashboard inside your app, shows [Server-Sent Events](docs/GUIDE.md#server-sent-events) live while a stream is still open, and decodes protobuf to JSON when you add rules for it. Its [Files](docs/GUIDE.md#files) tab browses, previews and changes the files your app keeps in its sandbox. It is built around zero code change: add it, start it with one line, and the rest of your app stays as it is.

**Status:** HTTP, live Server-Sent Events, WebSocket and NWConnection capture, protobuf decoding, the dashboard, System Info, export, previous sessions and the Files tab work today.

## Screenshots

<table>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/http-list.png" width="180" alt="The HTTP list with a search field, status filters and one row per request, each with a coloured method tag, and an SSE tag on a live and an ended event stream"><br><sub>HTTP list</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/inspector-response.png" width="180" alt="The Log Inspector's Response page with the summary, a body preview and the response headers"><br><sub>Log Inspector: Response</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/inspector-request.png" width="180" alt="The Log Inspector's Request page with the URL, method, body, query and headers"><br><sub>Log Inspector: Request</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/inspector-metrics.png" width="180" alt="The Log Inspector's Metrics page with timing bars for DNS, Connect, TLS and first byte, and body sizes"><br><sub>Log Inspector: Metrics</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/body-viewer.png" width="180" alt="The Body Viewer showing a JSON response, pretty-printed, with copy and share buttons"><br><sub>Body Viewer</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/inspector-events.png" width="180" alt="The Log Inspector on a live Server-Sent Events stream, with the event count in the summary and each event listed with its type, ID, time and data, one of them redacted"><br><sub>Log Inspector: live events</sub></td>
  </tr>
  <tr>
    <td align="center" valign="top"><img src="docs/screenshots/sockets-list.png" width="180" alt="The Sockets list with one NWConnection, one WebSocket and one external socket, each with a tag for its source"><br><sub>Sockets</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/socket-timeline.png" width="180" alt="A WebSocket timeline with sent and received frames, ping, pong and close events"><br><sub>Socket timeline</sub></td>
    <td align="center" valign="top"><img src="docs/screenshots/files.png" width="180" alt="The Files tab on a folder, with an icon, size and date for an image, a JSON file, a file with no extension and a property list, and a search field"><br><sub>Files</sub></td>
  </tr>
</table>

The [Example](Example) app produced these, and it's a quick way to try Cerebro: open `Example/CerebroExample.xcodeproj` and run it on a simulator.

## Getting started

### Requirements

iOS or iPadOS 16+ and Swift 5.9 or later. CI builds with Xcode 26. Cerebro needs no permissions and no `Info.plist` keys.

### 1. Install

Pick one of these three options. They all need the same code.

#### Swift Package Manager

In Xcode:

1. Choose **File > Add Package Dependencies**.
2. Enter `https://github.com/0xSiddhant/Cerebro.git`.
3. Set **Dependency Rule** to **Exact Version**, using the [latest release](https://github.com/0xSiddhant/Cerebro/releases/latest) number.
4. Add the **Cerebro** product to your app target. Add **CerebroProto** as well only if you decode protobuf.

In a `Package.swift`, with `X.Y.Z` as the [latest release](https://github.com/0xSiddhant/Cerebro/releases/latest):

```swift
.package(url: "https://github.com/0xSiddhant/Cerebro.git", exact: "X.Y.Z"),
```

```swift
.target(name: "MyApp", dependencies: [.product(name: "Cerebro", package: "Cerebro")]),
```

SPM also downloads `swift-protobuf`, because the package declares it. Only `CerebroProto` links it.

#### CocoaPods

Cerebro comes from Git and is never published to CocoaPods trunk, so a bare `pod 'Cerebro'` fails. Always include `:git`.

```ruby
platform :ios, '16.0'

target 'MyApp' do
  pod 'Cerebro', :git => 'https://github.com/0xSiddhant/Cerebro.git', :tag => 'vX.Y.Z'
end
```

Replace `X.Y.Z` with the [latest release](https://github.com/0xSiddhant/Cerebro/releases/latest), then run `pod install` and open the `.xcworkspace`. Pod tags start with `v`, and SPM versions don't.

#### XCFramework

1. Download [`Cerebro.xcframework.zip`](https://github.com/0xSiddhant/Cerebro/releases/latest/download/Cerebro.xcframework.zip) from the latest release and unzip it.
2. Drag `Cerebro.xcframework` into your project and tick your app target.
3. In the target's **General > Frameworks, Libraries, and Embedded Content**, set it to **Embed & Sign**. It's a dynamic framework, so without this the app crashes at launch with `Library not loaded: @rpath/Cerebro.framework/Cerebro`.

Capture only needs that one zip. To decode protobuf, also add [`CerebroProto.xcframework.zip`](https://github.com/0xSiddhant/Cerebro/releases/latest/download/CerebroProto.xcframework.zip) and [`SwiftProtobuf.xcframework.zip`](https://github.com/0xSiddhant/Cerebro/releases/latest/download/SwiftProtobuf.xcframework.zip) the same way. The release zips are built with Xcode 26, the only version CI tests, so use that or later.

### 2. Start Cerebro

Add one line as early as you can. Capture is added to a session's configuration when that configuration is created, so **a session or configuration made before `Cerebro.start()` isn't captured**. `URLSession.shared` is the one exception, because Cerebro reaches it another way.

UIKit:

```swift
import Cerebro
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Cerebro.start()
        return true
    }
}
```

SwiftUI:

```swift
import Cerebro
import SwiftUI

@main
struct MyApp: App {
    init() {
        Cerebro.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

Stored properties run first. If your `AppDelegate` or `App` has something like `let api = APIClient()`, that client exists before either method above runs, so create it after `Cerebro.start()` instead.

That one line is all most apps need. HTTP traffic and `URLSessionWebSocketTask` are captured from here on.

### 3. Open the dashboard

| Way | What it does |
|---|---|
| Floating button | Tap it to open the dashboard. Drag it to move it. Its number counts the requests since you last opened the dashboard |
| Shake | Hides or shows the floating button. It doesn't open the dashboard. In the simulator, use **Device > Shake** |
| `Cerebro.present()` | Opens the dashboard from your own debug menu or gesture. It does nothing while Cerebro is off |
| Close button | Top left of the dashboard. It returns you to your app |

`Cerebro.stop()` ends capture and removes the dashboard. A later `Cerebro.start()` begins a new session, and the one before it can still be read as a [previous session](docs/GUIDE.md#previous-sessions).

## Learn more

The [guide](docs/GUIDE.md) covers everything past setup:

| Topic | What's there |
|---|---|
| [Features](docs/GUIDE.md#features) | What Cerebro captures and what the dashboard shows |
| [Configuration](docs/GUIDE.md#configuration) | Every setting and its default |
| [Redaction](docs/GUIDE.md#redaction) | Hiding tokens, cookies and body fields. Nothing is redacted until you select it |
| [Traffic that needs code](docs/GUIDE.md#traffic-that-needs-code) | `NWConnection`, Starscream and Socket.IO |
| [Protobuf decoding](docs/GUIDE.md#protobuf-decoding) | Showing binary protobuf as JSON, with rules in code or in a `traffic_map.json` file |
| [System Info](docs/GUIDE.md#system-info) | Network status, addresses, performance, session totals, app and device info, and the opt-in public IP |
| [Previous sessions](docs/GUIDE.md#previous-sessions) | Reading the last session after a relaunch or a crash, and what's kept on disk |
| [Export](docs/GUIDE.md#export) | Sharing a request as cURL or JSON, or the whole session as HAR |
| [Files](docs/GUIDE.md#files) | Browsing, previewing, changing and sharing your app's files, and showing App Group containers |
| [When Cerebro runs](docs/GUIDE.md#when-cerebro-runs) | On in simulators and development-signed builds, off elsewhere unless you opt in |
| [What changes while Cerebro captures](docs/GUIDE.md#what-changes-while-cerebro-captures) | Side effects on your app's requests |
| [What Cerebro can't capture](docs/GUIDE.md#what-cerebro-cant-capture) | WKWebView, AVPlayer and other limits |
| [Troubleshooting](docs/GUIDE.md#troubleshooting) | Common problems and fixes |

## License

MIT. See [LICENSE](LICENSE).
