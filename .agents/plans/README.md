# Cerebro Plans — Index & Gates

Implement strictly in order. One plan = one branch from `develop` = one PR into `develop`, except PLAN-00. Plans 0–5 lead to 1.0; subsequent plans build on that release. Plan 99 holds work deliberately left for later.

Zero code change is the first priority of every plan, and each must work the same in all three install options: SPM, CocoaPods and a downloaded XCFramework. Every plan also follows the design principles in `rules/coding.md`: DRY, KISS, YAGNI, the architecture, and Swift best practices.

Each plan follows the same format: goal → gate → scope → decisions & reasoning → public API → task checklist → acceptance criteria → test checklist → open questions. The `new-plan` skill has the detail.

| # | Plan | Branch | Gate to start |
|---|---|---|---|
| ✅ 00 | Repository setup: SPM, CocoaPods, XCFrameworks, CI, Example app, agent files | `main`, initial commit only | Owner reviews the git rules before the commit |
| ✅ 01 | HTTP capture and base dashboard | `plan/1-http-capture` | PLAN-00 done |
| ✅ 02 | WebSockets, NWConnection and the Sockets tab | `plan/2-sockets` | PLAN-01 merged |
| ✅ 03 | Protobuf decoding and the Proto Config tab | `plan/3-proto` | PLAN-02 merged |
| 04 | [System info and export](PLAN-04-system-info.md) | `plan/4-system-info` | PLAN-03 merged |
| 05 | [Background sessions, persistence and 1.0](PLAN-05-background-and-1.0.md) | `plan/5-background-and-1.0` | PLAN-04 merged |
| 06 | [Server-Sent Events capture and live inspection](PLAN-06-sse.md) | `plan/6-sse` | PLAN-05 merged and `v1.0.0` released |
| 99 | [Response mocking and replay](PLAN-99-mocking-and-replay.md) | Named when scheduled | Reference only: after 1.0, pulled into a new numbered plan when scheduled |

A plan's file is deleted in the PR that finishes it, and its row here gets a ✅. After that the code and `context/notes.md` carry what matters.

Rules of engagement: never start a gated plan early, never modify a plan file unprompted, and list any deviation from a plan in the PR body.
