# PLAN-01 — HTTP capture and base dashboard

## Goal

One `Cerebro.start()` call captures each request's URL, method, headers, body, response, error and timings, and a floating trigger opens a dashboard that lists them. After this plan Cerebro is useful for HTTP on its own.

## Gate

PLAN-00 done. Single PR on `plan/1-http-capture`.

## Scope

**In:** configuration injection and `CustomURLProtocol`; one `Cerebro.start()` line, the Release gate and its opt-in; per-request timings, bytes and connection details from metrics; the ring buffer with count and body caps; decompression, pretty JSON, default redaction and console logging levels; `DashboardWindowManager`, `PassthroughWindow`, the floating trigger with shake, the tab bar shell, the HTTP tab and the Log Inspector.

**Out:** WebSockets and NWConnection (PLAN-02). Proto decoding and the collapsible tree (PLAN-03). System Info, export and download progress (PLAN-04). Background sessions, persistence and the notification trigger (PLAN-05). Mocking and replay (PLAN-99).

## Decisions & reasoning

### Zero code change comes first

This is the project's first priority. An app adds Cerebro, calls `Cerebro.start()` once, and changes nothing else. Every setting has a working default, and the code is the same for all three install options: SPM, CocoaPods and a downloaded XCFramework.

### Capture engine

`CustomURLProtocol` is injected into `URLSessionConfiguration.default` and `.ephemeral` by swizzling their getters. It is public API, and Cerebro owns the real session, so metrics are exact. Swizzling task `resume()` and delegate methods was rejected, and so was a local proxy or VPN.

⚠️ The getters don't reach `URLSession.shared`. A spike on an iOS 26.4 simulator showed the swizzled `.default` getter reaches `URLSession(configuration: .default)` and not `URLSession.shared`, while `URLProtocol.registerClass` does reach it. So `start` also registers the class, and `stop` unregisters it. Apps change nothing either way.

### One `Cerebro.start()` line stays

The owner's rule: drop the line if it can go, keep it if keeping it makes the project simpler. Spikes showed auto-start is possible, but keeping the line is simpler across every plan.

| Plan | With `Cerebro.start()` | With auto-start |
|---|---|---|
| PLAN-00 setup | Stays pure Swift | Needs Objective-C `+load` in all three builds, and SPM needs a separate target for it. A C constructor is silently dropped in a static Pod, and a pure-Swift loader fails to link |
| PLAN-01 HTTP | Settings exist before the first request | Needs a second settings route, or early traffic uses defaults. Needs guards for app extensions, test hosts and SwiftUI previews. A check runs in every build, including App Store builds |
| PLAN-02 sockets | No difference | No difference |
| PLAN-03 proto | Rules are passed at start | Generated rules must find themselves at runtime |
| PLAN-04 system info | Public IP opt-in is set at start | Needs the second settings route |
| PLAN-05 persistence | Custom redaction and "persistence off" hold from the first request | Neither can be promised without the second settings route |

Auto-start's real gains are no `import`, no `#if DEBUG`, and catching sessions created before the line runs. It stays open as a later addition in PLAN-99, since it would only call `start`.

Sessions created before `start` aren't captured, because their configurations predate the swizzled getters. The README tells apps to call it as early as possible.

### Release gate

Cerebro is on when the app runs on a simulator or is development-signed, and off otherwise unless the developer opts in at start. While it's off, no swizzling runs.

The check runs at runtime from the app's signing, in all three install options. A spike showed `#if DEBUG` in SPM source follows the app's configuration, but inside a prebuilt library every check reports Release, including `_isDebugAssertConfiguration()` and `@_alwaysEmitIntoClient`. A compile-time gate would make XCFramework users add code, and that breaks the first priority.

Development-signed means `embedded.mobileprovision` has `get-task-allow` set. Ad Hoc, TestFlight and App Store builds don't, so they stay off, which is what the spec wants for QA and store builds. The one difference from "on in Debug, off in Release" is that a Release build on a simulator or a development-signed device is also on. Neither can reach users.

⚠️ This hasn't been tested on a real device. If the check doesn't hold there, fall back to `#if DEBUG` for SPM and CocoaPods, with an explicit opt-in for XCFramework users, and tell the owner.

### Metrics are the source of truth

Timings, byte counts and connection details come from request metrics. Data callbacks only see the decoded body, so they miss header bytes and real wire size, and `Content-Length` reflects the compressed size.

### Compression

URLSession already decompresses standard HTTP responses, so Cerebro reports compression there and only decompresses what the app compressed itself.

| Case | What Cerebro does |
|---|---|
| Response with `Content-Encoding` gzip, deflate or br | Shows the encoding, wire vs decoded size, and the ratio |
| Request body the app compressed itself | Decompresses gzip and zlib for display |
| App-level compressed payloads | Detects by header or magic bytes, then decompresses gzip and zlib for display |
| zstd or brotli at the app level | Flags the body as compressed and shows it raw |

### The pipeline order is fixed, and the decoder slot exists now

At capture the chain is decompress → proto decode → redact, and every step is optional. Decompression comes first so proto decoding always receives plain bytes. Pretty-printing moves out of this chain, under "Performance comes from design" below. Decoders are plugins registered at start, so the core stays free of dependencies and PLAN-03 plugs in without changing it.

### Performance comes from design

The engine stays in Swift. A worst-case run on a body of about 1 MB, on an Apple M1 Mac in a Release build, took 7 ms for zlib decompression, 34 ms for JSON parsing and pretty-printing, and 34 ms for protobuf decoding to JSON. Decompression and JSON already run in Apple's native libraries, so C would gain little and add risk. These four rules matter more:

1. **The pipeline never delays a request.** Capture callbacks hand off to a background queue and return, so the app gets its response at full speed.
2. **Processing stops at the cap.** Capture stops buffering a body at the stored-body cap, decompression stops once its output passes the cap, and a body over the cap skips parsing. This also protects against a small compressed body that expands enormously.
3. **Pretty-printing happens on open.** The Log Inspector formats a body when a request is opened, and console `full` formats it when logging. Most captured requests are never opened, so most never pay for it.
4. **Dashboard updates are batched.** The store publishes changes at a fixed interval rather than once per request, so a burst of traffic can't flood the main thread.

⚠️ Rules 2 and 3 skip parsing, but redacting configured JSON keys needs a parse, and redaction must run before storage. So:

- With JSON keys configured, a JSON body under the cap is still parsed at capture, and the stored "raw" body is the redacted one.
- With JSON keys configured, a body that looks like JSON but can't be parsed, because it's over the cap or malformed, can't be redacted. Cerebro stores no text for it and marks it as withheld.
- With no JSON keys configured, which is the default, nothing needs parsing at capture.

Only that first case parses a body at capture. Pretty-printing stays on open in all of them, since it formats text that is already redacted.

### Storage caps

A ring buffer behind an actor holds the session, because capture callbacks arrive on arbitrary threads. It is capped by body size as well as count, because large bodies, not request count, cause out-of-memory crashes.

### Redaction runs before storage

The dashboard, console and later exports never hold the raw value. The accepted trade-off is that a redacted value can't be revealed later.

### Dashboard windowing

`DashboardWindowManager` owns a `PassthroughWindow` at `windowLevel = .statusBar + 1`, attached to the active `UIWindowScene`, with a modified `hitTest`. Touches outside Cerebro's views fall through to the app, and the dashboard never pushes onto the app's navigation stack. Presenting inside the host's hierarchy was rejected.

### Four tabs

The dashboard has four tabs: HTTP, Sockets, Proto Config and System Info. The spec says five but lists four, and the owner chose four. Log Inspector is a detail view opened from HTTP, and Previous session sits inside HTTP and Sockets. Each tab arrives with its own plan, so this plan ships the shell with the HTTP tab.

## Public API

| API | Purpose | Notes |
|---|---|---|
| `Cerebro.start(_:)` | Starts capture | The one required line; configuration is optional |
| `Cerebro.stop()` | Stops capture | |
| `Cerebro.present()` | Opens the dashboard | For the app's own debug menu |
| `CerebroConfiguration` | Everything set at start | Settings below |

| Setting | Default |
|---|---|
| Opt-in for distribution builds | Off |
| Console level: off, summary, full | Summary |
| Requests kept | 500, oldest dropped first |
| Stored body per request or response | 1 MB, then truncated and marked as truncated |
| Extra redacted header names, JSON keys, query parameters | None |
| Shake gesture | On |

## Task checklist

**Startup (`Sources/CerebroCore/Configuration/`, `Sources/Cerebro/Facade/`)**
- [ ] Give `CerebroConfiguration` the settings above
- [ ] Implement `Cerebro.start`, `stop` and `present`
- [ ] Release gate: simulator, or `get-task-allow` in `embedded.mobileprovision`, with the same code in all three install options

**Capture (`Sources/CerebroCore/Capture/`)**
- [ ] Inject `CustomURLProtocol` through the `.default` and `.ephemeral` getters
- [ ] Register it with `URLProtocol.registerClass` in `start`, and unregister it in `stop`
- [ ] Run each request through Cerebro's own internal session, and keep that session from being captured
- [ ] Read upload bodies from the body stream
- [ ] Stop buffering a body at the cap, and keep counting its size
- [ ] Pass the response to the app first, then hand the transaction to the pipeline on a background queue

**Models and store (`Sources/CerebroCore/Models/`, `Sources/CerebroCore/Store/`)**
- [ ] Transaction model holding every field below
- [ ] Actor-backed ring buffer with both caps; download task bodies are not stored
- [ ] Observer that batches updates, so the dashboard stays live through a burst

| Part | Fields |
|---|---|
| Request | URL, method, headers, query parameters, body, start time |
| Response | Status code, headers, decoded body, MIME type, end time |
| Error | Domain, code, description; cancelled vs failed |
| Timing | DNS, connect, TLS, request sent, first byte, total |
| Connection | Remote and local IP + port, HTTP version, TLS version, reused connection, cellular / expensive / Low Data Mode |
| Size | Bytes sent, bytes received on the wire, body bytes after decoding |

**Pipeline (`Sources/CerebroCore/Pipeline/`)**
- [ ] Chain of optional steps, with a decoder plugin slot
- [ ] Decompression per the table above, stopping once the output passes the cap
- [ ] Pretty JSON on demand, for the Log Inspector and console `full`
- [ ] Default redaction of `Authorization`, `Proxy-Authorization`, `Cookie` and `Set-Cookie`, plus the configurable names, keys and parameters
- [ ] Parse at capture only when JSON keys are configured, and withhold a JSON body that can't be parsed
- [ ] Console output at the three levels

**Dashboard (`Sources/Cerebro/Triggers/`, `Sources/Cerebro/UI/`)**
- [ ] `PassthroughWindow` and `DashboardWindowManager`
- [ ] Floating circular trigger: tap opens, draggable, snaps to the nearest edge, shows an error badge
- [ ] Shake hook that shows or hides the trigger
- [ ] Tab bar shell with the HTTP tab; PLAN-02 to PLAN-04 add the other three
- [ ] HTTP tab: request list with colour-coded status badges (2xx, 4xx, 5xx), search and filters
- [ ] Log Inspector: headers, query parameters, body (raw, or pretty JSON formatted when opened), timings, connection details, and the withheld and truncated markers
- [ ] MVVM view models for both screens

## Acceptance criteria

1. With one `Cerebro.start()` in a Debug build of the Example app, its HTTP traffic appears in the HTTP tab with the fields above, including traffic through `URLSession.shared`, with no other code change.
2. In a distribution-signed build with no opt-in, no swizzling runs and nothing is captured. With the opt-in, capture works. This holds in all three install options.
3. Timings and byte counts match request metrics, and a gzip response shows its encoding, wire size, decoded size and ratio.
4. Request 501 evicts the oldest, and a body over 1 MB is stored truncated and marked as truncated.
5. The four default headers and the configured values never appear raw in the store or the console.
6. Touches outside Cerebro's views reach the host app, and the host's navigation stack is untouched.
7. The trigger taps, drags, snaps and shows its error badge. Shake toggles it and can be turned off. `Cerebro.present()` opens the dashboard.
8. The three console levels behave as specified.
9. The app receives each response without waiting for the pipeline, and no pipeline step runs on the main thread.
10. Memory stays bounded for a response far larger than the cap, and for a small compressed body that expands far past it.
11. A burst of requests doesn't stall the dashboard or the host app's UI.
12. With no JSON keys configured and console logging below `full`, a captured body is not parsed or formatted until it's opened.
13. With JSON keys configured, a JSON body that can't be parsed stores no text and shows as withheld.
14. The `build-and-test` skill passes in all channels.

## Test checklist

**Unit**
- [ ] Ring buffer eviction and body truncation
- [ ] Decompression of gzip and zlib, magic-byte detection, and flagging of zstd and brotli
- [ ] Decompression stops at the cap, including a small input that expands far past it
- [ ] Pretty JSON, including invalid JSON
- [ ] Bodies over the cap and malformed bodies are withheld with JSON keys configured, and stored truncated without them
- [ ] Many store changes in a burst produce one batched update
- [ ] Redaction of headers, JSON keys and query parameters
- [ ] Pipeline order, with steps skipped
- [ ] Release gate, including parsing `get-task-allow` from a sample profile

**Integration**
- [ ] A request through a session built from each swizzled getter is captured
- [ ] A request through `URLSession.shared` is captured, and `stop` ends that capture
- [ ] An upload's body is read from its stream
- [ ] A cancelled request records as cancelled, not failed
- [ ] The response reaches the app before the pipeline runs, and the pipeline stays off the main thread

**Manual, on a device or simulator**
- [ ] Touch pass-through, trigger dragging and shake in the Example app
- [ ] Dashboard over a host app with its own navigation stack
- [ ] Release gate on a real device: on when development-signed, off when Ad Hoc signed
- [ ] Profile a burst of large responses on a real device, since the timings above came from a Mac. If one step causes a visible problem, raise it with the owner before changing anything

