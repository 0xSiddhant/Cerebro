# Project Notes

What the code, the spec and the rules can't tell you. Keep this short: edit it in place, and delete what stops mattering.

## Status

`v0.1.0` is released and has only placeholders for capture. PLAN-01 and PLAN-02 add HTTP and socket capture and the dashboard.

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
| Pipeline | Decompress, proto decode, redact. Pretty-print only on open | Most requests are never opened |
| Redacted headers | None by default. The developer selects `SensitiveHeader` cases, or names in `headers` | The owner's rule: Cerebro opts nothing out on its own. The spec has a fixed default list |
| Unredactable bodies | With JSON keys configured, a JSON body that can't be parsed is withheld, form fields are redacted one by one, and other text that names a key is withheld | Stopping at the cap skips parsing, and redaction comes first |
| Proto decoding | Stays at capture, and raw bytes are dropped when redaction changes the body | Undecoded bytes can't be redacted |
| Socket frames | Payloads use the stored-body cap | The spec caps frames by count only |
| Socket store | Also capped at 100 connections and 100 times the body cap of payload in all, taking from the socket idle longest | A reconnecting socket would otherwise fill a fresh 1,000-frame timeline every time |
| WebSocket open | Shown as Connecting at `resume`, and Opened at the first frame or pong | Only the app's delegate sees the handshake, and a refused upgrade must never look open |
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
| How should a URLProtocol handle redirects? | Tell the client, then hold the 3xx until `stopLoading` (followed) or 500 ms (refused, which sends no signal). Sending the 3xx straight away passed a small spike, but with a new session per request it failed about 1 run in 20 to 100: the app got the 302, or `URLSession.data(for:)` crashed. Never sending it hangs a refused redirect, and Apple's sample approach fails one with `NSCocoaErrorDomain 3072` |

## Worth knowing

- A URLProtocol can't read the app's session, so the side effects in the "What changes while Cerebro captures" section of `docs/GUIDE.md` follow from the design. Don't try to fix them without a new idea.
- Copy as cURL and the share sheet (for cURL and bodies) shipped with PLAN-01 at the owner's request, ahead of PLAN-04. PLAN-04 reuses `CurlCommand` and `CapturedContentSharing`, and still adds raw JSON and HAR export.
- A session delegate that answers a redirect just as the held 3xx goes out, about 500 ms in, can still crash `URLSession.data(for:)`. Nothing public can close that window, because a refusal sends no signal. Delegates that answer sooner never reach it.
- `Cerebro.xcodeproj` leaves out `SWIFT_APPROACHABLE_CONCURRENCY` and member import visibility on purpose, so the same sources compile the same way as in SPM.
