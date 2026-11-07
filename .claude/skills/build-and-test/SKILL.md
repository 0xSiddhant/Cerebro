---
name: build-and-test
description: Run Cerebro's full quality gate across SPM, the Example app, CocoaPods and the XCFrameworks. Use after finishing a plan task, before every PR, and whenever build or test health is in question.
---

# Build and test: Cerebro's quality gate

Run these in order. Stop at the first failure and report its output. Never open a PR with a step red.

The code builds as several modules in SPM and as one module in the Pod and the XCFramework, so passing one channel proves nothing about the others.

1. Package tests on an iOS simulator:

   ```sh
   xcodebuild test -workspace .swiftpm/xcode/package.xcworkspace -scheme Cerebro-Package \
     -destination 'platform=iOS Simulator,name=iPhone 17'
   ```

   The workspace is explicit because plain `xcodebuild` picks `Cerebro.xcodeproj`, which has no test target. To run one test, add `'-only-testing:CerebroCoreTests/defaultConfigurationBuilds()'`.

2. Example app:

   ```sh
   xcodebuild build -project Example/CerebroExample.xcodeproj -scheme CerebroExample \
     -destination 'platform=iOS Simulator,name=iPhone 17'
   ```

3. The `podspec-lint` skill.

4. The `build-xcframework` skill. This is also the strict-concurrency gate: warnings are errors in `Cerebro.xcodeproj`, so a data race fails here even when step 1 only warned.

If this Mac has no `iPhone 17` simulator, pick one from `xcrun simctl list devices available`.

Report one line per step, then details only for failures. If a plan defines acceptance criteria for the work in progress, list which are covered by tests and which are still manual.
