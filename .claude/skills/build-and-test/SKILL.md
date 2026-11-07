---
name: build-and-test
description: Run Cerebro's full quality gate across linting, SPM, the Example app, CocoaPods and the XCFrameworks, then review the diff against the coding rules. Use after finishing a plan task, before every PR, and whenever build or test health is in question.
---

# Build and test: Cerebro's quality gate

Run these in order, using the commands in `AGENTS.md`. Stop at the first failure and report its output. Never open a PR with a step red.

The code builds as several modules in SPM and as one module in the Pod and the XCFramework, so passing one channel proves nothing about the others.

1. **Lint** with `swift-format` and SwiftLint. If `swiftlint` isn't installed, run `brew install swiftlint`, or leave it to CI and say so.
2. **Package tests** on an iOS simulator. The workspace is explicit because plain `xcodebuild` picks `Cerebro.xcodeproj`, which has no test target.
3. **Example app** build.
4. **The `podspec-lint` skill.**
5. **The `build-xcframework` skill.** This is also the strict-concurrency gate: warnings are errors in `Cerebro.xcodeproj`, so a data race fails here even when step 2 only warned.
6. **Review the diff** against `.agents/rules/coding.md`. Linters can't judge these, so check each one:
   - **DRY:** does this add a second path, default or copy of something that exists?
   - **KISS:** is there a simpler design that still meets the plan? Does any protocol have one conformer and no test fake?
   - **YAGNI:** is anything here beyond what the plan lists?
   - **Architecture:** does traffic still flow one way, through small interfaces, with collaborators passed in?
   - **Swift:** are access levels as narrow as they can be, and can anything crash the host app?

If this Mac has no `iPhone 17` simulator, pick one from `xcrun simctl list devices available`.

Report one line per step, then details only for failures. If a plan defines acceptance criteria for the work in progress, list which are covered by tests and which are still manual.
