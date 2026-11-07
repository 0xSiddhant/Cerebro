# PLAN-99 — Response mocking and replay (reference only, never implemented wholesale)

Work deliberately left for later. When an item is scheduled, promote it into a new numbered plan file with the standard format, remove its row here, and log the decision in `memory/decisions.md`. Do not implement anything from this file directly.

| Idea | Notes |
|---|---|
| **Response mocking** | Canned responses for matched requests. Not before 1.0. Scoped in detail when its plan is written |
| **Replay** | Replay of captured requests. Not before 1.0. Scoped in detail when its plan is written |

## Not planned yet

| Idea | Notes |
|---|---|
| **Raw proto wire-format view** | Field numbers and types, for payloads with no schema |
| **macOS** | The core has no UIKit, so it ports |
| **Auto-start** | Removes the `Cerebro.start()` line. Spikes showed it works with Objective-C `+load`, but PLAN-01's trade-off kept the line as simpler. It can be added later without breaking anything, since it would only call `start` |
