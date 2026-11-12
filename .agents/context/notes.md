# Project Notes

What the code, the spec and the rules can't tell you. Keep this short: edit it in place, and delete what stops mattering.

## Status

`v0.1.0` is released and has only placeholders for capture. Everything through PLAN-06 is on `develop`. The owner wants PLAN-08, the Files tab, in `v1.0.0` too, so the release waits for it. PLAN-06 was gated on that release, and the owner chose to start it first.

Not yet proven: a full `release.yml` run on GitHub, the Release gate on a real device, and a burst of large responses on a real device. If the gate doesn't hold on a device, fall back to `#if DEBUG` for SPM and CocoaPods with an explicit opt-in for XCFramework users, and tell the owner.

## Where we differ from the spec

These win over the spec, which is older.

| Area | Decision | Why |
|---|---|---|
| Priority | Zero code change comes first, and all three install options behave the same | The owner's rule |
| Startup | Keep one `Cerebro.start()` line | Auto-start needs Objective-C `+load` in all three builds, because a C loader is silently dropped in a static Pod and a pure-Swift loader failed to link. It also needs a second settings route and guards for extensions, test hosts and previews. PLAN-99 keeps the idea |
| HTTP capture | Also use `URLProtocol.registerClass` | The swizzled getters miss `URLSession.shared` |
| Release gate | One runtime signing check, not `#if DEBUG` | A prebuilt XCFramework reports Release even in a Debug app |
| WebSocket hooks | Also hook `resume`, `sendPing`, `cancel(with:reason:)` and plain `cancel` | `send` and `receive` can't see open, close or ping |
| Trigger badge | Counts requests since the dashboard was last opened, not errors | The owner's rule |
| Dashboard | Four tabs, with Proto Config hidden when no decoder is registered | The spec says five but lists four |
| Public IP | Looked up at `https://api.ipify.org`, one fixed address | The spec names no service, and the owner chose it |
| Download progress | An Active downloads section on the System Info tab, for foreground downloads only | The spec doesn't say where. A background transfer has no row in the HTTP list until it ends |
| Raw JSON export | One request as a JSON document, from the Log Inspector | The Body Viewer already shares a body as a file, and HAR covers the session |
| Session totals | A running sum kept by the store, with hosts past 50 grouped together | Summing the stored requests would shrink as the oldest are dropped |
| Saved sessions | Sockets are saved too, one line per frame or event | The plan's tasks only named requests, but its criteria ask for the Sockets tab, and the owner chose it |
| Session file cap | The newest `requestLimit` requests and 50 MB, trimmed from the oldest | The spec sets no disk limit, and an append-only file outgrows the store. The owner chose it |
| Restore | The previous session is read when it's opened, not at launch | Launch stays free of disk reads, and most launches never open it |
| Persistence off | Removes what earlier launches saved | A developer turning it off expects nothing left on disk |
| Notification trigger | Removed. The dashboard opens from the floating button, a shake or `Cerebro.present()` | The owner found it too generic to be useful. It also needed the app's permission and delegate code, couldn't have its own layout without an app extension, and iOS sometimes dropped it |
| Clearing the HTTP list | Also clears those requests from the saved session, through a marker line | The file is append-only, and a cleared request shouldn't come back after a relaunch |
| Throughput | Bytes received on the wire divided by the request's whole duration. The System Info average only counts responses of 64 KB or more | Metrics have no separate download time, so a small response measures the server's delay |
| System Info layout | Three pages, Network, Traffic and Device, under a status card | The owner's rule: one long list was hard to use |
| Connection quality | Shown as Performance, with a rating from the average response time: Good under 300 ms, Fair under 1 s, else Slow | The owner found averaged timings unclear. The thresholds are a judgement, not a measurement |
| App and device info | A Device page with the app's name, version and bundle ID, and the device's model, system, memory and locale | The owner's rule. The spec has neither |
| Pipeline | Decompress, proto decode, redact. Pretty-print only on open | Most requests are never opened |
| Redacted headers | None by default. The developer selects `SensitiveHeader` cases, or names in `headers` | The owner's rule: Cerebro opts nothing out on its own. The spec has a fixed default list |
| Unredactable bodies | With JSON keys configured, a JSON body that can't be parsed is withheld, form fields are redacted one by one, and other text that names a key is withheld | Stopping at the cap skips parsing, and redaction comes first |
| Proto decoding | Stays at capture, and raw bytes are dropped whenever JSON keys are configured | A field the app's `.pb.swift` doesn't know is in the bytes but not in the JSON that was redacted |
| Undecoded protobuf | Withheld when JSON keys are configured, with or without a rule, and so is gRPC-web's base64 text | The plan only named bodies over the cap, but no undecoded protobuf can be redacted |
| Proto JSON keys | Proto field names, not lowerCamelCase | Redaction rules get written from the `.proto` file |
| gRPC-web framing | With a 5-byte strip on a gRPC body, the header's length limits the message | A frame of trailers can follow it, and the plan's plain strip couldn't decode that |
| Socket frames | Payloads use the stored-body cap | The spec caps frames by count only |
| Socket store | Also capped at 100 connections and 100 times the body cap of payload in all, taking from the socket idle longest | A reconnecting socket would otherwise fill a fresh 1,000-frame timeline every time |
| WebSocket open | Shown as Connecting at `resume`, and Opened at the first frame or pong | Only the app's delegate sees the handshake, and a refused upgrade must never look open |
| Server-Sent Events | Capture `text/event-stream` responses through the existing URLSession path as bounded, live parsed events | SSE is a long-lived HTTP response; waiting for completion can hide it indefinitely |
| SSE updates | An open stream reaches the store at most once per 250 ms, on top of the store's own batching | The plan only asked for batching. A stream that sends tokens can deliver hundreds of small chunks a second, and each update copies up to 1,000 events |
| SSE event text | An event type or ID that isn't UTF-8 is dropped, and the default type `message` is never redacted | The standard replaces bad bytes, but the linter wants failable decoding and the data is kept as bytes either way. The default type isn't something a server sent |
| SSE timeout | The 60-second idle timeout of Cerebro's session still applies to a stream, and the guide says so | A longer timeout for streams would remove a limit an app may rely on. A probe protocol saw a configuration timeout of 3600 arrive as 60 |
| Scope | PLAN-08 adds a Files tab that browses the app's sandbox | The owner's requirement. The spec describes a network inspector only |
| Files tab sharing | Quick Look's own share button shares a file with no privacy warning | No public API removes the button. The owner accepted it over dropping Quick Look, and Cerebro's own Share action still warns |
| Branches and releases | `develop` flow, with releases automated on `main` | The owner's rule. `rules/git.md` has it |
| Versions | Breaking commits are a minor bump below 1.0, and `1.0.0` needs a `Release-As` footer | The spec makes `v1.0.0` a deliberate Plan 5 step |

## What was measured

Don't repeat these without a new reason. All ran on an Apple M1 Mac, the UI ones on the simulator, so real iPhones will be slower.

| Question | Answer |
|---|---|
| SwiftUI content instead of UIKit? | No. Updates took 67-84 ms against 50 ms, and the worst live frame took 84-92 ms against 55-67 ms |
| SwiftUI `Text` for response bodies? | No. It took 2-3 s on 100 KB and never finished 1 MB, while `UITextView` took under 0.5 s |
| SwiftUI floating trigger? | No. It swallowed the host app's touches |
| C for speed? | No. On about 1 MB, zlib took 7 ms and JSON 34 ms, both already native, and SwiftProtobuf took 34 ms |
| Cost of capture? | 1,000 requests of 64 KB with the dashboard open, in a Release build, took 2.0 s against 1.8 s. It dropped 2 of about 149 frames against 0, the worst frame took 51 ms against 17 ms, and memory grew 38 MB against 8 MB |
| Memory on a huge response? | Bounded. A 200 MB response arrived in full, and peak memory went from 408 MB to 429 MB |
| Do the WebSocket hooks see `async` calls? | Yes, on iOS 18.5 and 26.4. The `async` forms call the same Objective-C methods as the completion-handler ones |
| Cost of a fast socket stream? | 30,000 frames in 5.5 s, in a Release build. Behind the host app there were no slow frames and the worst took 17 ms. With the timeline open, 4 of 315 frames went over 34 ms and the worst took 72 ms |
| Does a background transfer survive the app exiting? | Yes, on an iOS 26.4.1 simulator after `exit(0)` mid-transfer. iOS relaunched the app in the background, and the recreated session delivered full metrics for the whole transfer. A real device, a termination by the system and a force-quit are untested |
| How should a URLProtocol handle redirects? | Tell the client, then hold the 3xx until `stopLoading` (followed) or 500 ms (refused, which sends no signal). Sending the 3xx straight away passed a small spike, but with a new session per request it failed about 1 run in 20 to 100: the app got the 302, or `URLSession.data(for:)` crashed. Never sending it hangs a refused redirect, and Apple's sample approach fails one with `NSCocoaErrorDomain 3072` |

## Worth knowing

- A URLProtocol can't read the app's session, so the side effects in the "What changes while Cerebro captures" section of `docs/GUIDE.md` follow from the design. Don't try to fix them without a new idea.
- A whole-session HAR is built in memory, so at the worst case of 500 requests with two 1 MB bodies each it needs about as much again as the store holds. Streaming it to a file is the fix if that ever matters.
- A session delegate that answers a redirect just as the held 3xx goes out, about 500 ms in, can still crash `URLSession.data(for:)`. Nothing public can close that window, because a refusal sends no signal. Delegates that answer sooner never reach it.
- `Cerebro.xcodeproj` leaves out `SWIFT_APPROACHABLE_CONCURRENCY` and member import visibility on purpose, so the same sources compile the same way as in SPM.
