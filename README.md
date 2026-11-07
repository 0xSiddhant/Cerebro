# Cerebro

A debug-only network inspector for iOS apps. Cerebro captures HTTP, WebSocket and NWConnection traffic and shows it in an in-app dashboard, including compressed and protobuf payloads. It is built around zero code change: add it, start it with one line, and the rest of your app stays as it is.

**Status:** early development. The repository and its build channels are set up, but capture and the dashboard arrive in the coming releases, and no version has been tagged yet.

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

Call it as early as you can, because sessions created before it aren't captured. No other change is needed for HTTP or `URLSessionWebSocketTask` traffic.

## What Cerebro can't capture

- WKWebView traffic
- AVPlayer streams
- gRPC over SwiftNIO
- Sockets not routed through `MonitoredNWConnection` or `ExternalNetworkBridge`

## License

MIT. See [LICENSE](LICENSE).
