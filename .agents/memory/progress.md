# Progress Tracker

Update after every work session: status, branch or PR, notes. Statuses: `not-started` · `in-progress` · `in-review` · `blocked` · `done`.

**Current state: PLAN-00 is done and released as `v0.1.0`. PLAN-01 is next and has no open questions.**

| Plan | Title | Status | Branch / PR | Notes |
|---|---|---|---|---|
| PLAN-00 | Repository setup | done | `main` (initial commit only) | Released as `v0.1.0` |
| PLAN-01 | HTTP capture and base dashboard | not-started | `plan/1-http-capture` | |
| PLAN-02 | WebSockets, NWConnection and the Sockets tab | not-started | `plan/2-sockets` | |
| PLAN-03 | Protobuf decoding and the Proto Config tab | not-started | `plan/3-proto` | |
| PLAN-04 | System info and export | not-started | `plan/4-system-info` | |
| PLAN-05 | Background sessions, persistence and 1.0 | not-started | `plan/5-background-and-1.0` | |
| PLAN-99 | Response mocking and replay | not-started | | Scoped when the plan is written |

## Recent activity (newest first)

### 2026-11-07: design principles and linting

Made DRY, KISS, YAGNI, the architecture and Swift best practices binding in `coding.md`, with a review step in `build-and-test`. Added `swift-format` and SwiftLint to CI, and fixed the 20 findings they raised: missing public docs, three force unwraps in the Example app, and formatting. SwiftLint stays out of `Package.swift` and the podspec, so apps that use Cerebro never see it.

### 2026-11-07: performance rules added to the plans

Nothing implemented: plan only. Measured the pipeline's worst case, confirmed no C is needed, and added four performance rules to PLAN-01 to PLAN-05. Resolving them against redaction added the withheld-body rule and kept proto decoding at capture. The timings came from an Apple M1 Mac, so PLAN-01 profiles on a real device.

### 2026-11-07: develop branch and automated releases

Created `develop`. Implementation now branches from it and returns through PRs, and merging `develop` into `main` is what releases. `release.yml` works out the version, runs all CI, then updates the version, builds, tags, publishes and merges back.

Verified locally: 17 version scenarios, and a rehearsal of the workflow's git steps against a local bare repo, including `develop` moving mid-release. Not verified: `release.yml` hasn't run on GitHub. Its first full run will be the first `feat` or `fix` to reach `main`.

### 2026-11-07: v0.1.0 released

CI passed on the first push. `v0.1.0` was tagged by hand, before the automation existed, and has empty placeholders for capture. The Example sources ran on a simulator from public GitHub through all three install options.

### 2026-11-07: owner's answers applied to the plans

Nothing implemented: plan only. Made zero code change the first priority, resolved every open question, chose four dashboard tabs, and kept `Cerebro.start()` after a trade-off across every plan. Each GitHub Release now gives exact SPM and CocoaPods lines.

Verified: the Example sources ran on a simulator through a pod from a `v0.1.0` tag and through embedded XCFrameworks, and SPM `exact: "0.1.0"` resolved that tag and built. Auto-start spikes are in `decisions.md`. Not verified: the release workflow hasn't run, and the Release gate hasn't been tested on a real device.

### 2026-11-07: plan files written

Wrote PLAN-01 to PLAN-05 and PLAN-99 from the specification. Nothing implemented: plan only. Three spikes on real builds fed PLAN-01's open questions:

- `URLSession.shared` is not reached by the swizzled configuration getters, but `URLProtocol.registerClass` reaches it.
- `#if DEBUG` in SPM source follows the app's configuration.
- Nothing inside a prebuilt library can tell a Debug app from a Release app, including `@_alwaysEmitIntoClient`.

### 2026-11-07: PLAN-00 implemented

Set up SPM, CocoaPods, XCFrameworks, GitHub Actions, the Example app, the folder layout and the agent files. Added `origin` (`git@github.com:0xSiddhant/Cerebro.git`), which is empty and has not been pushed to.

Verified locally: package tests on an iPhone 17 simulator, `pod lib lint`, all three XCFrameworks with a client compiled against them, and the Example app running on a simulator with all four traffic types succeeding. Not verified: the GitHub Actions workflows have not run, and were only parsed as YAML.
