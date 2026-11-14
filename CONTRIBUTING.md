# Contributing to Cerebro

Thanks for helping. This page covers how to report a problem, set up the project, check a change, and get it merged.

## Before you write code

- **Bugs:** open an issue with the iOS version, the install option (SPM, CocoaPods or XCFramework), what you did, what you expected and what happened. If a request was captured wrongly, attach its cURL or HAR export, with any secrets removed.
- **Features:** open an issue first, so we can agree on the approach before you build it. Cerebro's first priority is that adding it never changes how an app is written, and a feature that fits that is much more likely to be merged.

## Set up

You need a Mac with Xcode 26, which CI uses, and an iOS simulator.

```sh
git clone https://github.com/0xSiddhant/Cerebro.git
cd Cerebro
git checkout develop
git config core.hooksPath .githooks   # formats and lints staged Swift files before each commit
brew install swiftlint                # code-quality lint; CI runs it too
gem install cocoapods                 # only to lint the podspec
```

`Example/CerebroExample.xcodeproj` is an app that uses the package from your clone, with a sample of every kind of traffic. Run it to try a change for real.

## Check your change

CI runs all of these on every pull request, and each one must pass:

```sh
# Formatting, crash paths and public docs (ships with Xcode)
xcrun swift-format lint --strict --recursive Sources Tests Example

# Code quality
swiftlint lint --strict

# Build and run every test on an iOS simulator
xcodebuild test -workspace .swiftpm/xcode/package.xcworkspace -scheme Cerebro-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# The Example app
xcodebuild build -project Example/CerebroExample.xcodeproj -scheme CerebroExample \
  -destination 'platform=iOS Simulator,name=iPhone 17' -skipPackagePluginValidation

# CocoaPods, which compiles everything as one module
pod lib lint Cerebro.podspec

# The XCFrameworks, with warnings as errors
Scripts/build-xcframework.sh
```

If you don't have an iPhone 17 simulator, pick one from `xcrun simctl list devices available`. `swift build` and `swift test` build for the Mac, so they don't check anything here.

## Rules every change follows

The full rules are in [`.agents/rules/coding.md`](.agents/rules/coding.md). These matter most:

- **Zero code change.** An app adds Cerebro with `Cerebro.start()` and nothing else. Capture is automatic wherever iOS allows it, and a new public API is only for traffic nothing automatic can reach.
- **Three install options, one behaviour.** SPM builds `CerebroCore`, `Cerebro` and `CerebroProto` as separate modules, while CocoaPods and the XCFramework merge them. So file and type names must be unique across `Sources/`, and an import of `CerebroCore` sits inside `#if SWIFT_PACKAGE`.
- **Never crash the host app.** No `!`, `try!`, `as!`, `fatalError` or `precondition` in `Sources/`. A failure logs to the console and drops that capture.
- **Strict concurrency** is on everywhere. Swift 5.9 and iOS 16 are the floor.
- **Privacy.** Redaction runs before anything is stored, and nothing leaves the device except the public IP lookup, which is off by default.
- **Dependencies.** SwiftProtobuf is the only one, and only `CerebroProto` uses it. `CerebroCore` never imports UIKit.
- **UI** is programmatic UIKit in Cerebro's own window. Nothing loads from bundles, and every colour comes from `DashboardTheme`.
- **Tests** use Swift Testing. Every `public` declaration has a `///` comment.
- **Docs.** A change to behaviour or public API updates [`docs/GUIDE.md`](docs/GUIDE.md), and the README if setup changes.

[`.agents/context/`](.agents/context) describes the architecture, where files go, and decisions that were already measured, so check it before redesigning something.

## Branches, commits and pull requests

The full rules are in [`.agents/rules/git.md`](.agents/rules/git.md).

- Branch from `develop` and name the branch `<type>/<slug>`, such as `fix/redaction-crash`.
- Write commits as [Conventional Commits](https://www.conventionalcommits.org): `<type>(<scope>): <subject>`, with a header of 72 characters at most. The subject is imperative and starts lowercase, such as `fix(core): keep redirects in order`. A body, if any, says why, in lines of 100 characters at most.
  - Types: `feat`, `fix`, `chore`, `docs`, `test`, `ci`, `refactor`
  - Scopes, optional: `core`, `ui`, `proto`, `generator`, `example`, `ci`, `docs`, `release`
- Open the pull request into `develop`, never `main`. Give it a title in the same format, because a squash merge keeps only the title and the release reads it. Say what changed and why and how you tested it, and add light and dark screenshots for a UI change.
- The maintainer reviews and merges.

## Releases

The maintainer releases by merging `develop` into `main`. The release workflow works out the version from the commit types since the last release, runs every check again, updates the version, adds the release's section to [`CHANGELOG.md`](CHANGELOG.md), tags it and publishes the GitHub Release.

| Commits since the last release | Next version |
|---|---|
| A `feat` | Minor, such as 1.0.0 to 1.1.0 |
| Only `fix` | Patch, such as 1.0.0 to 1.0.1 |
| `!` after the type, or a `BREAKING CHANGE:` line | Major, such as 1.0.0 to 2.0.0 |
| Only `chore`, `docs`, `test`, `ci` or `refactor` | No release |

Never edit versions, `CHANGELOG.md` or tags by hand.

## AI coding agents

Agents start from [`AGENTS.md`](AGENTS.md), which has the same rules and the reading order.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
