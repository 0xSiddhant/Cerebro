# Cerebro Architecture

This is the target design from the specification. `.agents/memory/progress.md` says what exists so far.

Cerebro is a layered, one-way pipeline: traffic is captured, decoded, stored, then shown. Zero code change is the first priority, so the host app touches one small facade and, in most apps, only one line of it.

```
Host app            URLSession, WebSocket and NWConnection traffic
   │
   ▼
Capture layer       URLProtocol, config injection, socket hooks, wrappers     (CerebroCore)
   │
   ▼
Pipeline            decompress → decode proto → redact, in the background     ◀── Decoder plugins: CerebroProto, custom
   │
   ▼
Transaction store   actor-backed ring buffer with size caps                   ◀── Network info: path monitor, interfaces, public IP
   │
   ▼
Dashboard           UIKit tabs: HTTP, sockets, proto, system info             (Cerebro)  ◀── Triggers: floating trigger, shake, notification
```

## Patterns

| Pattern | Applied to | Why |
|---|---|---|
| Layered architecture | Capture → pipeline → store → UI | Each layer can be replaced and tested on its own |
| Facade | `Cerebro.start`, `stop`, `present` | The host app touches one small API |
| Strategy | URLProtocol for foreground sessions, a delegate proxy for background sessions | Both engines feed the same pipeline |
| Decorator | `MonitoredNWConnection` wraps `NWConnection` | Captures state and bytes without hooking Network.framework |
| Chain of responsibility | The body pipeline | Order matters and every step is optional |
| Plugin | Decoders registered at start | The core stays free of dependencies |
| Actor-backed repository | Ring buffer store | Capture callbacks arrive on arbitrary threads |
| Observer | Store → dashboard | Batched live updates while the dashboard is open |
| MVVM | Dashboard view controllers | View logic can be tested without the UI |

## Capture sources

| Source | Captured by | Change needed in the app |
|---|---|---|
| Foreground `URLSession` | `CustomURLProtocol` injected into session configurations | None |
| `URLSession.shared` | `CustomURLProtocol` registered with `URLProtocol.registerClass`, because the swizzled getters don't reach it | None |
| Background `URLSession` | Delegate-proxy engine | None |
| `URLSessionWebSocketTask` | Hooks on its public `send`, `receive`, `resume`, `sendPing(pongReceiveHandler:)` and `cancel(with:reason:)` methods | None |
| `NWConnection` | `MonitoredNWConnection` wrapper | Create the wrapper instead of `NWConnection` |
| Starscream, Socket.IO, others | `ExternalNetworkBridge` | One call per frame or event |

WKWebView, AVPlayer streams and gRPC over SwiftNIO are out of reach, and the README says so.

## Performance

Speed comes from design, not language. The engine stays in Swift, because decompression and JSON already run in Apple's native libraries.

1. The pipeline runs on a background queue and never delays a request or a frame.
2. Processing stops at the stored-body cap.
3. Bodies are pretty-printed when opened, not when captured.
4. Dashboard updates are batched.

Redaction still comes first. With JSON keys configured, a JSON body is parsed at capture, and one that can't be parsed stores no text and shows as withheld. Proto decoding stays at capture for the same reason.

## Where an app still writes code

| What | Code needed | Why it can't be automatic |
|---|---|---|
| Starting Cerebro | One line: `Cerebro.start()` | It could be, but keeping it is simpler across every plan. See "Why `Cerebro.start()` stays" |
| `NWConnection` | Create `MonitoredNWConnection` instead | Network.framework has no Objective-C methods to hook |
| Starscream, Socket.IO, others | One `ExternalNetworkBridge` call per frame or event | Their engines bypass URLSession |
| Proto rules | One argument to `Cerebro.start`, for apps that decode protobuf | Those rules live in the app's target |
| Notification redirect trigger | One forwarded call, optional | The host app owns the notification delegate |

### Why `Cerebro.start()` stays

Spikes showed auto-start is possible, but it needs Objective-C `+load` in all three builds: a C constructor is silently dropped in a static Pod, and a pure-Swift loader fails to link. It would also need a second settings route, guards for app extensions, test hosts and SwiftUI previews, and a check running in every build, including App Store builds. All that saves one line. The cost of keeping the line is that sessions created before it aren't captured, so it should run as early as possible.

## Release gate

Every install option uses the same runtime check, because `#if DEBUG` inside a prebuilt XCFramework reports Release even in a Debug app. Cerebro is on when the app runs on a simulator or is development-signed, meaning `embedded.mobileprovision` has `get-task-allow` set. It is off otherwise, which covers Ad Hoc, TestFlight and App Store builds, unless the developer opts in at start.

## Modules

| Module | Contains | Depends on |
|---|---|---|
| `CerebroCore` | Capture, pipeline, store, metrics, models, configuration | Foundation, Network |
| `Cerebro` | Public facade, triggers, dashboard UI | `CerebroCore`, UIKit |
| `CerebroProto` | Proto rules and decoder | `CerebroCore`, SwiftProtobuf |
| `CerebroProtoPlugin` | Build-tool plugin that runs the generator on the app's target | SPM only |
| `CerebroProtoGenerator` | Reads `traffic_map.json` and `.pb.swift` files, writes `ProtoRule.generated`; shipped as `cerebro-proto-gen` for Run Script phases | Foundation |

The split keeps SwiftProtobuf out of apps that don't use protobuf, and lets the core be tested without UIKit.

## One source tree, three builds

| Channel | Modules | How sources reach each other |
|---|---|---|
| SPM | `CerebroCore`, `Cerebro`, `CerebroProto` | `#if SWIFT_PACKAGE` imports; `Cerebro` re-exports the core, so apps only `import Cerebro` |
| CocoaPods | One `Cerebro` module; subspecs `Core`, `UI`, `Proto` choose the sources | Same module, no imports |
| XCFramework | `Cerebro` (core and UI), `CerebroProto`, `SwiftProtobuf` | `CerebroProto` imports `Cerebro` under `CEREBRO_PROTO_STANDALONE` |

`Cerebro.xcodeproj` compiles `Sources/` directly into three framework targets through synchronized folders. Details that aren't obvious from the project file:

- `SwiftProtobuf.framework` is compiled from `.build/checkouts/swift-protobuf`, so `swift package resolve` must run first. `Package.resolved` pins the version, and `Scripts/build-xcframework.sh` runs the resolve.
- `CerebroProto.framework` links `SwiftProtobuf.framework` dynamically, because the app's generated `.pb.swift` types must conform to the same module.
- `.gitkeep` files are excluded through `EXCLUDED_SOURCE_FILE_NAMES`, or the synchronized folders would copy them into the framework as resources.
- The script ends by compiling a client against all three XCFrameworks, because a broken `.swiftinterface` otherwise fails only in a consumer's build.
