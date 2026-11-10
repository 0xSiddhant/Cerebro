# PLAN-05 — Persistence and 1.0

## Goal

Keep the previous session readable after a relaunch or crash, and ship `v1.0.0`.

## Gate

PLAN-04 merged. Single PR on `plan/5-background-and-1.0`. Its `Release-As: 1.0.0` commit makes the next `develop` → `main` merge release `v1.0.0`.

## Scope

**In:** the on-disk session store with previous-session restore, the previous-session view, the notification redirect trigger, complete `README.md` setup and `docs/GUIDE.md` documentation, and the `v1.0.0` release.

**Out:** mocking and replay (PLAN-99). Compile-time removal in Release, which was rejected.

## Decisions & reasoning

### JSON Lines in Caches

Each session is one JSON Lines file in the app's Caches directory, appended as each request completes. A crash loses at most the requests still in flight, and there is no database schema to migrate.

### Redaction runs before anything is written

Persisted sessions stay in the app's Caches directory, already redacted.

### Disk writes stay off the request path

Each completed request is appended on a background queue, so file I/O never delays a request. Each append still happens per request, not in batches, or a crash could lose completed requests. Writes store what the store holds, so caps, truncation and withheld bodies carry over.

### The host app owns notifications

The host app owns the notification delegate and permission, so it forwards taps with one call. The trigger is off by default.

## Public API

| API | Purpose | Notes |
|---|---|---|
| Persistence setting | Keeps the previous session | On by default, can be turned off |
| Previous sessions kept setting | Sessions on disk | Default 1, replaced at each launch |
| Notification redirect call | Opens the dashboard from a tap | Off by default; the host app forwards the tap |

## Task checklist

**Store (`Sources/CerebroCore/Store/`)**
- [ ] Append each completed request to a JSON Lines file in Caches, on a background queue
- [ ] Keep the configured number of sessions, replaced at each launch
- [ ] Restore the previous session on launch

**Dashboard (`Sources/Cerebro/UI/`, `Sources/Cerebro/Triggers/`)**
- [ ] Previous-session view: the last launch's log, read-only, in the HTTP and Sockets tabs
- [ ] Notification redirect trigger

**Release**
- [ ] Complete `README.md` setup and `docs/GUIDE.md` configuration and capture-limit documentation
- [ ] Add a commit with a `Release-As: 1.0.0` footer, then run the `release` skill

## Acceptance criteria

1. After a relaunch or a crash, the previous session is readable and read-only in the HTTP and Sockets tabs.
2. A crash loses at most the requests still in flight.
3. Turning persistence off writes nothing to disk.
4. One previous session is kept by default, and the count is configurable.
5. No file on disk holds a redacted value in raw form.
6. A forwarded notification tap opens the dashboard, and nothing happens with the trigger off.
7. Disk writes never delay a request and never run on the main thread.
8. The README and guide accurately document setup, configuration, persistence, background-session capture, and capture limits.
9. Merging `develop` into `main` releases `v1.0.0` with all its binaries.
10. The `build-and-test` skill passes in all channels.

## Test checklist

**Unit**
- [ ] JSON Lines append and restore, including a truncated last line after a crash
- [ ] Session rotation
- [ ] Redaction before write, including withheld bodies

**Integration**
- [ ] Restore after a relaunch
- [ ] Writes stay off the main thread

**Manual**
- [ ] Crash the Example app and read the previous session
- [ ] Forward a notification tap
- [ ] Install `v1.0.0` through SPM, CocoaPods and the XCFramework
