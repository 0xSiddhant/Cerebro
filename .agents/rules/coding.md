# Coding Rules

## First priority: zero code change

- Adding Cerebro must not change how an app is written. Capture is automatic wherever iOS allows it.
- Add a code-level API only when nothing automatic can reach that traffic, or when it improves performance. Any such API is additive: an app that doesn't use it still works.
- Every setting has a working default, so `Cerebro.start()` needs no arguments.
- SPM, CocoaPods and a downloaded XCFramework must behave the same and need the same code.

## Design principles

Every change follows these, and the `build-and-test` skill reviews each diff against them. If one conflicts with zero code change, host app safety or privacy, those win.

**DRY: each fact and behaviour lives in one place**

- Every capture source feeds the same pipeline and store. A new source never gets a second path.
- HTTP bodies and socket frames share the decoders, and live and previous-session views share the screens.
- Defaults live only in `CerebroConfiguration`.
- Extract shared code at the third use. Two similar lines beat a wrong abstraction.

**KISS: the simplest design that meets the plan**

- Prefer plain functions, structs and system APIs over custom abstractions and new frameworks.
- A protocol needs two conformers, or a test that needs a fake. Capture engines and decoders qualify.
- If a piece needs a long comment to explain how it works, simplify it first.

**YAGNI: only what the current plan asks for**

- Build what the active plan lists. No settings, options or hooks "for later".
- A setting exists only if the spec or a plan names it.
- A seam for a later plan must name that plan, like PLAN-01's decoder slot for PLAN-03.
- Delete a placeholder in the PR that replaces it.

**System design and architecture**

- `.agents/context/architecture.md` is binding. Traffic flows one way, and each layer reaches the next through a small interface.
- `Cerebro.start` is the composition root: it builds the objects and passes them through initializers. Runtime hooks may read one shared reference set there, and nothing else is a singleton.
- Keep logic away from side effects. A pipeline step takes input and returns output, with no UI or global state, so it can be tested alone.
- Inject what tests must control, such as the clock, file locations and the session.

## Boundaries

- Traffic flows one way: capture → pipeline → store → dashboard. Decoders, network info and triggers plug in from the side.
- `CerebroCore` holds capture, pipeline, store, metrics, models and configuration. It never imports UIKit or SwiftProtobuf.
- `Cerebro` holds the public facade, triggers and dashboard UI.
- `CerebroProto` is the only module that uses SwiftProtobuf. Apps that don't use protobuf must never link it.
- There is no Objective-C or C target and no `+load`. Unsafe pointers appear only at C API boundaries such as `getifaddrs`.
- SwiftProtobuf is the only dependency. Adding another needs a logged decision.

## One source tree, three builds

SPM builds `CerebroCore`, `Cerebro` and `CerebroProto` as separate modules. The Pod compiles all of them into one `Cerebro` module. The XCFramework merges `CerebroCore` and `Cerebro` into `Cerebro`, and keeps `CerebroProto` separate. CI builds all three on every push, so the difference never surprises a release.

- A file in `Sources/Cerebro` that uses a core type starts with:

  ```swift
  #if SWIFT_PACKAGE
  import CerebroCore
  #endif
  ```

- A file in `Sources/CerebroProto` that uses a core type starts with:

  ```swift
  #if SWIFT_PACKAGE
  import CerebroCore
  #elseif CEREBRO_PROTO_STANDALONE
  import Cerebro
  #endif
  ```

- File names must be unique across `Sources/CerebroCore` and `Sources/Cerebro`. A repeat fails the Xcode build with "filename used twice".
- Type names must be unique across all three modules, even internal ones, because the Pod merges them.
- A core symbol used by another module must be `public`, because `internal` stops at the SPM module boundary.
- `Cerebro` is both a module and a public enum, so inside the framework's own interface `Cerebro.X` resolves to the enum. Never add another public type named after a module.
- `Cerebro.xcodeproj` needs `-alias-module-names-in-module-interface` on `Cerebro` and `CerebroProto`. Without it the XCFramework's interface doesn't compile.

## Swift

- Swift 5.9 tools, Swift 5 language mode, strict concurrency complete in every channel. Capture callbacks arrive on arbitrary threads, so state they touch is `Sendable` or behind an actor.
- Strict concurrency reports warnings in Swift 5 mode, so `Cerebro.xcodeproj` treats warnings as errors. Never pass that setting on the command line: it collides with `-suppress-warnings` on the SwiftProtobuf package.
- Use the names the spec uses: `CustomURLProtocol`, `DashboardWindowManager`, `PassthroughWindow`, `MonitoredNWConnection`, `ExternalNetworkBridge`, `ProtoRule`.
- Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/): clarity at the call site, and no abbreviations.
- Stay within Swift 5.9 and iOS 16. That rules out typed throws, `@Observable` and `Mutex`.
- Default to `struct`, `enum` and `let`. Mark every class `final` unless it's designed to be subclassed.
- Keep access narrow: `private` first, then `internal`, and `public` only for host-app API or what another module needs. Every `public` declaration has a `///` comment.
- Never crash the host app. No `!`, `try!`, `as!`, `fatalError` or `precondition` in `Sources/`, except the unavailable `init?(coder:)` on a view controller. A failure logs to the console and drops that capture.
- New concurrency uses actors and `async`/`await`. `@unchecked Sendable` needs a comment proving it's safe.
- Stored closures capture `self` weakly unless the object must stay alive until they run.

## Linting

CI fails on any finding from either tool, and each check has one owner.

- `swift-format` owns formatting, force unwraps, force tries and public docs. It ships with Xcode, and `.swift-format` configures it.
- SwiftLint owns code quality, such as complexity limits, weak delegates and simpler standard library use. `.swiftlint.yml` configures it.
- SwiftLint is a contributor tool. Never add it to `Package.swift` or `Cerebro.podspec`, because apps that use Cerebro must not resolve, download or run it. CI pins its version with a container.
- The `.githooks/pre-commit` hook formats staged files and lints what is being committed. CI remains the gate. It's a contributor tool that never reaches apps using Cerebro.

## Performance

- Capture callbacks hand off to a background queue and return. The pipeline, disk writes and exports never run on the request path or the main thread.
- Stop processing at the stored-body cap, in capture, decompression and parsing.
- Format on open. Only the redaction of configured JSON keys and proto decoding parse at capture.
- Batch updates to the dashboard. Disk appends are the exception: they stay per request, for the crash guarantee.
- Don't reach for C or another language without a measured problem on a real device and a logged decision.

## Host app safety

- Cerebro stays off in distribution builds unless the developer opts in at start. It decides at runtime from the app's signing, because a prebuilt XCFramework can't see the app's build configuration. While it's off, no swizzling runs and `MonitoredNWConnection` is a zero-cost pass-through.
- The dashboard lives in its own `PassthroughWindow`. It never swallows touches outside its own views and never pushes onto the app's navigation stack.
- Every store has a cap, by size as well as by count. Large bodies, not request count, cause out-of-memory crashes.

## Privacy

- Redaction runs before anything is stored, so the dashboard, console, exports and disk never hold the raw value. A performance shortcut never overrides this: a body that can't be redacted is withheld, not stored.
- No data leaves the device except the opt-in public IP lookup, and that call is excluded from the logs.
- Export shows a warning before sharing.

## UI

- Programmatic UIKit only: no storyboards, no SwiftUI, nothing loaded from bundles.
- MVVM, so view logic can be tested without the UI.

## Testing

- Tests use Swift Testing (`import Testing`, `@Test`, `#expect`) and live in `Tests/`.
- They run through SPM on an iOS simulator. `Cerebro.xcodeproj` has no test target.
- Use `try #require` instead of force unwraps.
