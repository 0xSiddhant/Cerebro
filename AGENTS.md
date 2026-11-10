# AGENTS.md — Cerebro

Instructions for every coding agent in this repository. `CLAUDE.md` imports this file and adds Claude-specific notes, so the instructions live in one place.

Cerebro is a debug-only Swift package that captures an iOS app's HTTP, WebSocket and NWConnection traffic and shows it in an in-app dashboard. It targets iOS 16+ and ships through Swift Package Manager, a Git-sourced CocoaPod and XCFrameworks.

The full specification is the [Cerebro spec](https://claude.ai/artifact/Vao3XbYhftkMkmScDSkoVg). What an agent needs day to day lives in `.agents/`. Where the spec and `.agents/context/notes.md` differ, the notes win, because they are newer.

## First priority: zero code change

Adding Cerebro must not change how an app is written. Everything is automatic wherever iOS allows it. Add a code-level API only when nothing automatic can reach that traffic, or when it improves performance. The one required line is `Cerebro.start()`, and `.agents/context/architecture.md` lists every other place code is needed.

Users choose one of three install options, and all three are first-class: SPM, CocoaPods, or a downloaded XCFramework. Each must behave the same and need the same code.

## Required reading (every session, before writing any code)

1. `.agents/context/architecture.md`: layers, modules, the three build shapes
2. `.agents/context/tech-stack.md`: chosen tools and why
3. `.agents/context/project-structure.md`: where files go
4. `.agents/rules/git.md`: branches, commits, PR flow (non-negotiable)
5. `.agents/rules/coding.md`: code conventions and boundaries
6. `.agents/context/notes.md`: where we differ from the spec, and what was already measured
7. The active plan file in `.agents/plans/`, if there is one (the status table says which)


## Current plan

PLAN-05, persistence and 1.0, is next. See `.agents/plans/README.md` for the order and gates.

## Commands

Plain `xcodebuild` picks `Cerebro.xcodeproj`, so package commands name the workspace. `swift build` and `swift test` target the Mac, not iOS, so they are not a valid check.

```sh
# Package: build and run every test on an iOS simulator
xcodebuild test -workspace .swiftpm/xcode/package.xcworkspace -scheme Cerebro-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# Package: run one test (add this to the command above)
'-only-testing:CerebroCoreTests/defaultsMatchTheSpec()'

# Example app
xcodebuild build -project Example/CerebroExample.xcodeproj -scheme CerebroExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation

# Lint: formatting, crash paths and public docs (ships with Xcode)
xcrun swift-format lint --strict --recursive Sources Tests Example

# Lint: code quality (a contributor tool: brew install swiftlint)
swiftlint lint --strict

# Enable the pre-commit hook once per clone
git config core.hooksPath .githooks

# CocoaPods: compiles every subspec as one module
pod lib lint Cerebro.podspec

# XCFrameworks: output in build/xcframeworks
Scripts/build-xcframework.sh

# The generator binary for Run Script phases: output in build/generator
Scripts/build-generator.sh
```

## Code conventions

`.agents/rules/coding.md` has the full rules. These four break builds or the host app:

- One source tree compiles three ways: several modules in SPM, one module in the Pod and the XCFramework. Guard cross-module imports, and keep file and type names unique across `Sources/CerebroCore` and `Sources/Cerebro`.
- `CerebroCore` never imports UIKit or SwiftProtobuf.
- Strict concurrency is on everywhere, and warnings are errors in `Cerebro.xcodeproj`.
- The dashboard is programmatic UIKit in its own window. It never swallows the host app's touches or touches its navigation stack.

Every change also follows that file's design principles: DRY, KISS, YAGNI, the architecture, and Swift best practices.

## Working rules

- Implement exactly one plan file at a time, in order. Do not start a plan whose gate is not cleared.
- If a plan file explicitly overrides a rule in `.agents/rules/`, the plan file wins for that plan only.
- Add to `.agents/context/notes.md` only what the code, the spec and the rules can't tell you: a change from the spec, or a measurement worth keeping. Edit it in place, and delete what stops mattering.
- Delete a plan's file in the PR that finishes it.
- Never modify plan files without being asked. Ask the owner when a plan is ambiguous instead of guessing.
- Project skills live in `.claude/skills/`, and `.agents/skills` is a symlink to that directory so every agent finds the same ones: `build-and-test`, `podspec-lint`, `build-xcframework`, `release`, `new-plan`, `context-sync`. Create or edit a skill only in `.claude/skills/`. Run `build-and-test` before every PR.
