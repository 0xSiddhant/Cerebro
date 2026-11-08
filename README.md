# Cerebro

A debug-only network inspector for iOS apps. Cerebro captures HTTP, WebSocket and NWConnection traffic and shows it in an in-app dashboard, including compressed and protobuf payloads. It is built around zero code change: add it, start it with one line, and the rest of your app stays as it is.

**Status:** early development. HTTP capture and the dashboard work today. WebSocket and NWConnection capture, protobuf decoding, system info and background sessions arrive in the coming releases.

## Requirements

iOS 16+ and Swift 5.9 or later.

## Installation

Pick one of these three options. Each [GitHub Release](https://github.com/0xSiddhant/Cerebro/releases) lists the exact lines for that version, so replace `1.2.4` below with the version you want.

### 1. Swift Package Manager

```swift
.package(url: "https://github.com/0xSiddhant/Cerebro.git", exact: "1.2.4")
```

Link the `Cerebro` product. Link `CerebroProto` too if you decode protobuf.

### 2. CocoaPods

Cerebro is consumed from Git and is never published to CocoaPods trunk.

```ruby
pod 'Cerebro', :git => 'https://github.com/0xSiddhant/Cerebro.git', :tag => 'v1.2.4'
```

To decode protobuf, add `pod 'Cerebro/Proto'` the same way. A Pod is one module, so `ProtoRule` comes from `import Cerebro`, and there is no `import CerebroProto`.

### 3. XCFramework

1. Download `Cerebro.xcframework.zip` from a GitHub Release and unzip it.
2. Add `Cerebro.xcframework` to your app target and set it to **Embed & Sign**.

To decode protobuf, add `CerebroProto.xcframework` and `SwiftProtobuf.xcframework` the same way. Use this bundled SwiftProtobuf rather than one from SPM or Pods, because your generated `.pb.swift` types must conform to the same module `CerebroProto` was compiled against.

## Usage

```swift
import Cerebro

Cerebro.start()
```

Call it as early as you can, because sessions created before it aren't captured. No other change is needed for HTTP traffic, including `URLSession.shared`.

Tap the floating button to open the dashboard, and shake the device to hide or show the button. The number on it counts the requests since you last opened the dashboard. To open the dashboard from your own debug menu, call `Cerebro.present()`. `Cerebro.stop()` ends capture and removes the dashboard.

In the dashboard, a request's page has Copy cURL and Share buttons at the top. In the list, swipe a request to copy its cURL, or long-press it for the same options. A body has its own copy and share buttons. Redacted values stay as placeholders, and Cerebro warns you before anything is shared.

Cerebro runs on simulators and in development-signed builds. It stays off in Ad Hoc, TestFlight and App Store builds unless you set `allowsDistributionBuilds`.

### Settings

Every setting is optional.

```swift
Cerebro.start(CerebroConfiguration(
    consoleLevel: .full,
    redaction: RedactionRules(jsonKeys: ["password"])
))
```

| Setting | Default | What it does |
|---|---|---|
| `allowsDistributionBuilds` | `false` | Runs capture in distribution-signed builds too |
| `consoleLevel` | `.summary` | `.off`, one line per request, or `.full` with headers and bodies |
| `requestLimit` | `500` | Requests kept. The oldest is dropped first |
| `bodyLimit` | 1 MB | Bytes stored for each request or response body. Longer bodies are marked as truncated |
| `redaction` | Nothing extra | Extra header names, JSON keys and query parameters to redact |
| `isShakeGestureEnabled` | `true` | Whether a shake shows or hides the button |

`Authorization`, `Proxy-Authorization`, `Cookie` and `Set-Cookie` are always redacted before anything is stored. Setting `jsonKeys` makes Cerebro parse JSON bodies at capture, and a JSON body it can't parse is withheld rather than stored unredacted.

## What changes while Cerebro captures

Cerebro sends each request through its own session, which has these side effects in builds where it runs:

- Settings on your `URLSessionConfiguration` other than headers don't apply, such as timeouts, cellular access and cookie handling.
- The `urlSession(_:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)` upload progress callback doesn't fire.
- HTTP Basic, Digest and NTLM logins answered by a session delegate aren't answered, so your app receives the 401.
- A redirect your session delegate refuses arrives about 500 ms later. Followed redirects aren't delayed.

Certificate pinning and client certificates keep working, because those challenges still reach your delegate.

Cerebro keeps both the request and response body of up to 500 requests, so it can hold about 1 GB at worst. Lower `requestLimit` or `bodyLimit` if your app moves many large bodies.

## What Cerebro can't capture

- WKWebView traffic
- AVPlayer streams
- gRPC over SwiftNIO
- Sockets not routed through `MonitoredNWConnection` or `ExternalNetworkBridge`

## License

MIT. See [LICENSE](LICENSE).
