# Progress Tracker

Update after every work session: status, branch or PR, notes. Statuses: `not-started` · `in-progress` · `in-review` · `blocked` · `done`.

**Current state: PLAN-00 is done. PLAN-01 is next and has no open questions.**

| Plan | Title | Status | Branch / PR | Notes |
|---|---|---|---|---|
| PLAN-00 | Repository setup | done | `main` (initial commit only) | GitHub Actions hasn't run yet, because it needs a push |
| PLAN-01 | HTTP capture and base dashboard | not-started | `plan/1-http-capture` | |
| PLAN-02 | WebSockets, NWConnection and the Sockets tab | not-started | `plan/2-sockets` | |
| PLAN-03 | Protobuf decoding and the Proto Config tab | not-started | `plan/3-proto` | |
| PLAN-04 | System info and export | not-started | `plan/4-system-info` | |
| PLAN-05 | Background sessions, persistence and 1.0 | not-started | `plan/5-background-and-1.0` | |
| PLAN-99 | Response mocking and replay | not-started | | Scoped when the plan is written |

## Recent activity (newest first)

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
