---
name: release
description: Cut a Cerebro release as a vX.Y.Z tag on main. Use when the owner says "release" or "cut vX.Y.Z".
---

# Release

`.github/workflows/release.yml` runs on a `vX.Y.Z` tag. It fails if the tag doesn't match `s.version` in `Cerebro.podspec`, builds the XCFrameworks, and publishes a GitHub Release with them attached. The release notes come from `Scripts/release-notes.sh` and give that version's exact SPM and CocoaPods lines. This skill covers everything around that.

Hard rules: tags go on `main` only. Never force-push. Never push to CocoaPods trunk. The owner merges PRs and approves the tag.

1. **Preflight** on a clean, current `main`: every plan in this release is `done` in `.agents/memory/progress.md`, and the `build-and-test` skill passes.
2. **Context sync:** run the `context-sync` skill so the docs match the code being shipped.
3. **Version bump** through a normal PR: `s.version` in `Cerebro.podspec`, and `MARKETING_VERSION` in `Cerebro.xcodeproj` and `Example/CerebroExample.xcodeproj`. Stop for the owner to merge.
4. **Tag**, after the owner approves:

   ```sh
   git checkout main && git pull
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```

5. **Confirm:** the `Release` workflow succeeds, and the GitHub Release shows the install lines for this version and has `Cerebro`, `CerebroProto` and `SwiftProtobuf` `.xcframework.zip` assets. From PLAN-03 on it also needs the `cerebro-proto-gen` binary. Report the release URL.
