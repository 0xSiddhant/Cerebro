---
name: build-xcframework
description: Build Cerebro, CerebroProto and SwiftProtobuf as XCFrameworks and prove a client compiles against them. Use when changing public API, Cerebro.xcodeproj or the Package.resolved pin, before a release, or as a step of build-and-test.
---

# Build XCFrameworks

```sh
Scripts/build-xcframework.sh
```

Output lands in `build/xcframeworks`: three `.xcframework` folders and a `.zip` of each. Never commit them.

The script resolves the package, archives one `XCFrameworks` scheme for device and simulator, creates the XCFrameworks, compiles a small client against them, then zips them.

When a step fails:

- **The client compile fails.** A public API change broke the textual interface, or the API a client uses changed. Update the client in the script to match any intended change.
- **"is not a member type of enum 'Cerebro.Cerebro'".** `-alias-module-names-in-module-interface` is missing from a target. `Cerebro` the enum shadows `Cerebro` the module, and that flag is what makes the interface compile.
- **"filename used twice".** Two files share a name across `Sources/CerebroCore` and `Sources/Cerebro`. Rename one.
- **A warning fails the archive.** Warnings are errors on the `Cerebro` and `CerebroProto` targets. Fix the warning. Don't turn the setting off.
- **SwiftProtobuf sources are missing.** The target compiles `.build/checkouts/swift-protobuf`. Run `swift package resolve`.

A SwiftProtobuf upgrade can add build requirements. Compare its `SwiftProtobuf.podspec` with the `SwiftProtobuf` target's settings in `Cerebro.xcodeproj`, which mirror the package's default traits.
