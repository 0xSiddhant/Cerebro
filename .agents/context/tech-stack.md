# Tech Stack (decided: do not swap without a logged decision)

| Concern | Choice | Why |
|---|---|---|
| Platforms | iOS and iPadOS 16+ | Covers every API Cerebro uses; macOS can come later because the core has no UIKit |
| Language | Swift, 5.9 tools, Swift 5 mode, strict concurrency complete | Capture callbacks arrive on arbitrary threads, so the compiler should catch data races |
| HTTP capture | `URLProtocol` injected into session configurations and registered with `URLProtocol.registerClass` | Public API; Cerebro owns the real session, so metrics are exact; registration reaches `URLSession.shared` |
| Release gate | Runtime check of the app's signing | The same in all three install options; a prebuilt XCFramework can't see the app's build configuration |
| Background capture | Delegate-proxy engine | URLProtocol doesn't cover background sessions |
| Socket capture | Hooks on `URLSessionWebSocketTask`, `MonitoredNWConnection`, `ExternalNetworkBridge` | No call-site changes where hooks can reach; a wrapper where they can't |
| Storage | Actor-backed ring buffer capped by count and size, plus JSON Lines in Caches | Large bodies cause out-of-memory crashes; no database schema to migrate |
| UI | Programmatic UIKit in a `PassthroughWindow` | Full control over windows and touches; nothing to load from bundles |
| Proto decoding | SwiftProtobuf 1.27.0 up to, not including, 2.0.0 | Apps with `.pb.swift` files already link it; 1.27.0 is the first version where `Message` is `Sendable` |
| Tests | Swift Testing on an iOS simulator | The package is iOS-only |
| Linting | `swift-format` from Xcode, and SwiftLint 0.62.2 in a CI container | Rules nothing enforces get skipped. Neither tool reaches apps that use Cerebro |
| Distribution | SPM, a Git-sourced CocoaPod, or a downloaded XCFramework, all first-class | The user picks; CocoaPods is Git-sourced because trunk goes read-only on December 2, 2026 |
| CI | GitHub Actions on `macos-26` | Has Xcode 26, CocoaPods and the `iPhone 17` simulator |
| Versioning | SemVer, tags `vX.Y.Z`, worked out from Conventional Commits by `release.yml` | Versions can't drift, and `1.0.0` takes a deliberate `Release-As` footer |
| License | MIT | |
