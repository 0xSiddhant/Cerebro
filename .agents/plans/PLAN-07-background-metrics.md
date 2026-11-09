# PLAN-07 — Background transfer metrics

## Goal

Capture transfers made through a background `URLSession` with no change to the app. Each one appears in the HTTP tab with its URL, status, headers, timing, connection details and sizes, but never its file or body. `URLProtocol` can't see these sessions, so Cerebro misses them today.

## Gate

PLAN-04 merged, and the owner has settled open question 1. Single PR on `plan/7-background-metrics`.

## Scope

**In:** a hook on session creation for background configurations, a delegate proxy that reads metrics and completion, a not-stored request body for uploads, the Log Inspector's wording, background samples in the Example app, documentation, and tests.

**Out:** the contents of a background transfer's file or body, live progress or rows for transfers still running, one row per redirect hop, keeping rows across launches (PLAN-05), and sessions created before `Cerebro.start()`.

## Decisions & reasoning

### Verified on a simulator first

A throwaway app on an iOS 26.4.1 simulator, with a local server, ran real background transfers.

| Question | Result | If it had gone the other way |
|---|---|---|
| Does a hook on `+sessionWithConfiguration:delegate:delegateQueue:` see Swift's `URLSession(configuration:delegate:delegateQueue:)`? | Yes, and `URLSession(configuration:)` goes through it too | Hook task creation instead, which has many more entry points |
| Do callbacks reach a proxy, with the app still getting everything? | Yes. The app received `didFinishDownloadingTo` with the file present, `didReceive` data, `didFinishCollecting`, completion and `urlSessionDidFinishEvents` | Add methods to the delegate's own class |
| Does a `URLProtocol` on a background configuration run? | No. `canInit` was never called, and the transfers still succeeded | Reuse the foreground engine, and skip this plan |
| Are the metrics complete? | Yes. A download reported 2,048 response body bytes and an upload 4,096 request body bytes, with headers, remote address and timing | Promise less in the dashboard |
| Does a transfer survive the app exiting? | Yes. iOS relaunched the app in the background, and the session recreated with the same identifier delivered full metrics covering the whole 6-second transfer | Document rows as lost across a relaunch |
| In what order do metrics and completion arrive? | Metrics first, every time, including after a cancel and a relaunch | Handled either way, because no documentation promises it |
| Can the `delegate` getter be hooked to hide the proxy? | Yes. The app saw its own delegate, and callbacks still reached the proxy | Accept and document the visible proxy |
| What does a redirect look like? | One task with 2 attempts. `originalRequest` is the first URL, `currentRequest` and `response` the last | See "One row per transfer" |
| Which request has the real headers? | `originalRequest` only has what the app set. `currentRequest` also has the configuration's and the system's | Use `originalRequest` |
| Is a cancel reported? | Yes, with metrics and `-999` | Nothing changes |
| Is a refused connection reported? | Not within 20 seconds. The system keeps retrying | Nothing changes, but the limit stays documented |
| Can any process use a background session? | No. The transfer service rejected an app with no `application-identifier` entitlement, and every task failed at once with `-1` | See the test checklist |

Not verified: a real device, a termination by the system rather than `exit(0)`, a force-quit, HTTPS or HTTP/2, and iOS versions other than 26.4.1. A manual test covers the device, and if the metrics there are incomplete, the guide must say so before this ships.

### A delegate proxy, because nothing else sees these sessions

The transfer runs in a system process, so only the session's delegate hears about it. When the hook sees a configuration with an `identifier`, it passes a proxy in place of the app's delegate, and every other session is left alone. The proxy answers `responds(to:)` and `forwardingTarget(for:)` from the app's delegate, so everything it doesn't implement goes straight there, unchanged. It holds that delegate strongly, as `URLSession` does.

Rejected: adding methods to the delegate's class, because it reaches every instance and subclass, and reading task properties through KVO, which has no metrics.

### Metrics only

The owner's decision. The proxy never opens a file or reads a body, and `didFinishDownloadingTo` passes straight through, because iOS deletes the temporary file when that callback returns. Capturing contents would need a second buffering path, for bytes a developer rarely opens.

### One row per transfer, describing its last hop

A row is built from `currentRequest`, falling back to `originalRequest`. That way the URL, status, headers, timing and connection all describe the same final hop, as the last row of a redirected foreground request does, and headers set on the configuration are included. Sizes count every hop, as they already do.

Rejected: `originalRequest`, whose status and timing would belong to a different URL, and one row per hop built from `transactionMetrics`, which is more code for a rare case.

### Times come from the metrics

A transfer can start in an earlier launch, so the hook may never see it begin. `startDate` and `endDate` come from `taskInterval`, falling back to the moment of completion if metrics never arrive.

### Handle either callback order

The proxy pairs metrics and completion by task identifier under a lock, and submits one `RawExchange` when it has both. If completion comes first, it waits the same 250 ms as `CustomURLProtocol`, whose `metricsGrace` becomes `internal`. An entry lasts only until its task completes, so what's held is limited by the transfers in flight. These callbacks run on the app's delegate queue, so the proxy only stores and hands off, and the pipeline does the rest in the background.

### Hide the proxy from the app

Without this, `session.delegate` returns the proxy, and code that casts it back to its own class breaks. A hook on the `delegate` getter unwraps it. The class comes from `type(of:)` on the returned session, so no private name appears in the code, and a missing method means no hook rather than a crash.

### After `Cerebro.stop()`

The creation hook is removed. Existing sessions keep their proxies, because a session's delegate can't be replaced, so each proxy checks `HTTPCaptureEngine.active` and only forwards when capture is off. The getter hook stays installed for the same reason. It only unwraps a proxy, and it's only ever installed if capture was on.

### Upload bodies show as not stored, with their size

An upload's file never reaches the app's process, so a request body of zero bytes would look like no body at all. `RawExchange.requestBody` becomes optional, and `nil` means "exists but wasn't captured". `TransactionBuilder` then records `.notStored` with the byte count from the metrics, or no body if that count is zero. An internal `requestBodyBytes` on `URLSessionTaskMetrics` keeps this out of the public `TransferSize`.

## Public API

None. An app adds nothing, and `Cerebro.start()` has to run before the session is created, as it does for every other session.

## Task checklist

**Capture (`Sources/CerebroCore/HTTP/Capture/`)**
- [ ] `BackgroundSessionHooks.swift`: hook `+sessionWithConfiguration:delegate:delegateQueue:`, wrap the delegate when `configuration.identifier` is set, and restore the original on uninstall
- [ ] Hook the `delegate` getter once per session class, doing nothing if the method is missing, and keep it installed after stop
- [ ] `BackgroundSessionProxy.swift`: forward through `responds(to:)` and `forwardingTarget(for:)`, implement the metrics and completion callbacks, and pass both on to the app's delegate
- [ ] Pair metrics and completion by task identifier under a lock, in either order, and make `metricsGrace` `internal` to reuse it
- [ ] Build the `RawExchange` from `currentRequest ?? originalRequest`, `task.response`, the error and the metrics, with both bodies `nil` and times from `taskInterval`
- [ ] Only forward when `HTTPCaptureEngine.active` is `nil`
- [ ] Install and uninstall from `HTTPCaptureEngine`

**Pipeline (`Sources/CerebroCore/HTTP/Pipeline/`, `Sources/CerebroCore/HTTP/Models/`)**
- [ ] Make `RawExchange.requestBody` optional, with the foreground path unchanged
- [ ] In `TransactionBuilder`, turn a `nil` request body into `.notStored` with the metrics' byte count, or no body at zero
- [ ] Add an internal `requestBodyBytes` to the `URLSessionTaskMetrics` extension in `TransactionMetrics.swift`

**Dashboard (`Sources/Cerebro/UI/LogInspector/`)**
- [ ] Reword "Not stored, because it's a download" in `LogInspectorViewModel.swift` so it also fits uploads and other background transfers

**Example (`Example/CerebroExample/`)**
- [ ] Add background download and upload samples to `TrafficSample`, with a small delegate object, because background sessions don't allow completion handlers

**Documentation**
- [ ] Remove "Background `URLSession` transfers, for now" from `docs/GUIDE.md`, and add a section on what's captured and its limits: no file or body, one row per transfer, shown only once finished, a transfer iOS keeps retrying stays unseen until it ends, `Cerebro.start()` must run first, and rows are in memory only
- [ ] Update the PLAN-05 mention in `.agents/context/project-structure.md`
- [ ] Add the relaunch result to "What was measured" in `.agents/context/notes.md`

## Acceptance criteria

1. A download and an upload through a background `URLSession` created after `Cerebro.start()` appear in the HTTP tab with no app changes, with URL, status, headers, timing, connection and sizes.
2. Neither a file nor a body is ever read or stored. An upload's request body and a download's response body show as not stored, with their byte counts.
3. The app's delegate receives every callback it would without Cerebro, once each, and the downloaded file is still there during `didFinishDownloadingTo`.
4. `session.delegate` returns the app's own delegate, or `nil` if it passed none.
5. A transfer that finishes after iOS relaunches the app appears in that launch's log, with times covering the whole transfer.
6. A redirected transfer is one row describing its last hop, with sizes counting every hop.
7. A cancelled transfer appears as cancelled.
8. Configured redaction applies to the row's URL and headers before anything is stored.
9. Sessions without an `identifier` behave exactly as they did, and foreground capture is unchanged.
10. After `Cerebro.stop()`, proxies only forward and no new rows appear. In a build where Cerebro is off, no hook is installed.
11. `docs/GUIDE.md` accurately documents the behaviour and its limits.
12. The `build-and-test` skill passes in all channels.

## Test checklist

SPM test processes may be turned away by the transfer service, as the entitlement-free app was, so these tests don't rely on a background transfer completing. Real metrics come from running the proxy on an ordinary session against `LocalHTTPServer`, and the Example app covers real background sessions. Every test that installs a hook goes in the serialized `CaptureTests` suite, because hooks are process-wide.

**Unit**
- [ ] Metrics then completion, completion then metrics, and completion with no metrics each submit one exchange
- [ ] An unknown selector forwards to the app's delegate, `responds(to:)` follows it, and a `nil` delegate is safe
- [ ] `TransactionBuilder` records `.notStored` for a `nil` request body with bytes, and no body at zero
- [ ] `requestBodyBytes` sums every attempt
- [ ] A `nil` engine forwards and records nothing

**Integration**
- [ ] The proxy on a foreground session against `LocalHTTPServer` produces a row with real timing and sizes, and the app's delegate still gets its callbacks
- [ ] The creation hook wraps a background configuration and leaves `.default` alone
- [ ] `session.delegate` returns the app's own delegate, and `nil` when it passed none
- [ ] Redaction of the URL and headers
- [ ] Stopping restores the creation hook

**Manual**
- [ ] Example app on a simulator: background download and upload appear with metrics
- [ ] A real device: the app is suspended and terminated by the system mid-transfer, and the row appears after the relaunch with complete metrics
- [ ] A real device: a force-quit, to record what iOS does and whether anything appears

## Open questions

1. **PLAN-05 also lists this work.** Its capture task, first acceptance criterion and first integration test all cover a delegate-proxy engine, and plans run strictly in order. Recommendation: run this plan after PLAN-04, in place of those items, and remove them from PLAN-05, which needs the owner's approval because plan files aren't edited unprompted. The alternative is to fold this plan's decisions into PLAN-05 and delete this file.
2. **Should the HTTP list mark background transfers?** Recommendation: no. Nothing asks for it, and the not-stored body already tells them apart in the Log Inspector.
