# Project Notes

What the code, the spec and the rules can't tell you. Keep this short: edit it in place, and delete what stops mattering.

## Status

`v0.1.0` is released and has only placeholders for capture. Not yet proven: a full `release.yml` run on GitHub, and the Release gate on a real device.

## Where we differ from the spec

These win over the spec, which is older.

| Area | Decision | Why |
|---|---|---|
| Priority | Zero code change comes first, and all three install options behave the same | The owner's rule |
| Startup | Keep one `Cerebro.start()` line | Auto-start needs Objective-C `+load` in all three builds, because a C loader is silently dropped in a static Pod and a pure-Swift loader failed to link. It also needs a second settings route and guards for extensions, test hosts and previews. PLAN-99 keeps the idea |
| HTTP capture | Also use `URLProtocol.registerClass` | The swizzled getters miss `URLSession.shared` |
| Release gate | One runtime signing check, not `#if DEBUG` | A prebuilt XCFramework reports Release even in a Debug app |
| WebSocket hooks | Also hook `resume`, `sendPing` and `cancel(with:reason:)` | `send` and `receive` can't see open, close or ping |
| Dashboard | Four tabs, with Proto Config hidden when no decoder is registered | The spec says five but lists four |
| Pipeline | Decompress, proto decode, redact. Pretty-print only on open | Most requests are never opened |
| Unredactable bodies | With JSON keys configured, a JSON body that can't be parsed is withheld | Stopping at the cap skips parsing, and redaction comes first |
| Proto decoding | Stays at capture, and raw bytes are dropped when redaction changes the body | Undecoded bytes can't be redacted |
| Socket frames | Payloads use the stored-body cap | The spec caps frames by count only |
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

## Worth knowing

- `Cerebro.xcodeproj` leaves out `SWIFT_APPROACHABLE_CONCURRENCY` and member import visibility on purpose, so the same sources compile the same way as in SPM.
