# PLAN-99 — Response mocking and replay (reference only, never implemented wholesale)

Work deliberately left for later. When an item is scheduled, promote it into a new numbered plan file with the standard format, and remove its row here. Do not implement anything from this file directly.

| Idea | Notes |
|---|---|
| **Response mocking** | Canned responses for matched requests. Not before 1.0. Scoped in detail when its plan is written |
| **Replay** | Replay of captured requests. Not before 1.0. Scoped in detail when its plan is written |

## Not planned yet

| Idea | Notes |
|---|---|
| **Raw proto wire-format view** | Field numbers and types, for payloads with no schema |
| **tvOS dashboard** | The first of the three dashboards when one is scheduled. PLAN-10 brings capture, the console and a session file to tvOS, and no dashboard. UIKit is there, so the dashboard is adapted, not rewritten: every screen has to work with the focus engine, and the trigger needs a remote gesture, since there's no touch or shake. The clipboard, share sheet, document picker, Quick Look, pull to refresh, swipe actions and inset grouped tables don't exist, so copy, export and file import go, and previews fall back to the Body Viewer. One plan, touching most of the 36 UIKit files. That list is from reading the code, not from a compiler, until PLAN-10's spike counts the errors |
| **Native macOS dashboard** | The largest. PLAN-10 brings capture to macOS and the UIKit dashboard to Mac Catalyst. A native app has no UIKit, so it needs a new AppKit view layer over the existing view models, about 4,100 lines of views, with a window in place of the overlay and a menu item or shortcut as the trigger. The Files tab must stay inside the app's sandbox container |
| **watchOS dashboard** | Left for the future by the owner on 2026-11-14. watchOS has no UIKit views, so it would be SwiftUI, which `rules/coding.md` forbids in the dashboard and `context/notes.md` measured as slower. It needs the owner to lift that rule for watchOS only, for a reduced dashboard on a very small screen. Until then a watch's session file opens on an iPhone, through PLAN-10 |
| **Live stream to a Mac** | Watching a device's session on a Mac as it happens. The section below has the detail |
| **Auto-start** | Removes the `Cerebro.start()` line. Spikes showed it works with Objective-C `+load`, but PLAN-01's trade-off kept the line as simpler. It can be added later without breaking anything, since it would only call `start` |

## Live stream to a Mac

The owner asked for this to be kept as an idea on 2026-11-14. The spec lists a Mac companion app as a non-goal, so scheduling it changes the spec, and `context/notes.md` gets a row then.

**What it is.** While a developer or a tester uses the app on a device, the session appears on a Mac as it happens: requests, socket frames and, after PLAN-09, log lines. A large screen and a keyboard are where traffic is easiest to read, and the device's own screen stays free for the app.

**Why it fits.** Nothing new has to be invented for the data. Each store already writes every finished record to the session file through its journal, redacted, one JSON line each. A stream is a second place those same lines go: capture, pipeline and store stay as they are, and the receiving end reads the lines the way it reads a saved session. It builds on PLAN-10, which makes the core run on macOS and lets a dashboard open another device's session file.

**Smallest steps first.** Each is useful alone, and each can be its own plan.

| Step | What ships | Cost |
|---|---|---|
| 1. Follow a simulator | A simulator's session file is already on the Mac's disk. A command-line tool finds the running app's file and follows it, printing a line per request or writing a copy | Small. No network, no pairing, no permission. The package already ships one Mac tool, `cerebro-proto-gen` |
| 2. Stream from a device | The dashboard gets a "Stream to a Mac" switch. The device connects to the tool on the Mac over the local network and sends each line as it's written. The tool saves a growing session file | Medium. Pairing, encryption and the local network permission, below |
| 3. Watch it live | A dashboard opens that growing session and updates as lines arrive, read-only. It's PLAN-10's Open Session File, made live | Small on Mac Catalyst, where the UIKit dashboard runs. A native Mac app needs the native macOS dashboard above first |

**What it must not break.**

- **Privacy.** The rule is that no data leaves the device except the opt-in IP lookup. A stream is data leaving the device continuously, so it's off until someone turns it on from the dashboard, each launch, after the same warning as a share. It sends only what the stores hold, which is already redacted. It stays on the local network, and it never runs while the release gate is closed.
- **Pairing and encryption.** An open port that hands out an app's traffic to anyone on the Wi-Fi isn't acceptable. The Mac shows a short code, the device asks for it, and the connection is encrypted with a key made from it.
- **Zero code change.** Finding the Mac with Bonjour needs `NSBonjourServices` and `NSLocalNetworkUsageDescription` in the app's `Info.plist`, which is a change to the app. Typing or scanning the Mac's address avoids Bonjour, and the spike below says whether it avoids the keys.
- **Host app safety.** Sending happens on a background queue with a bounded backlog, as capture does. A slow or lost Mac drops lines from the stream, never from the device's own stores, and never delays a request.
- **Three install options.** The Mac tool is built from the package, like the generator, so each option gets it the same way.

**What a spike must settle.**

- Whether a connection from the device to an address on the local network shows the permission prompt without any `Info.plist` key, and what the prompt says.
- Whether Network.framework's pre-shared-key TLS works between an iOS device and a Mac tool with a key made from a six-digit code.
- Whether a device attached by cable can reach the Mac without Wi-Fi.
- What following the session file costs when the app writes thousands of lines a second.

**Rejected for now.**

- A viewer in the browser, served by the device. It needs no Mac software, but it puts a web server and a second interface in HTML and JavaScript inside every app that links Cerebro.
- Sending each request to the system log, to read in Console.app. It needs no network, but entries are short, bodies don't fit, and public values in the system log end up in sysdiagnoses.
- A cloud relay. Data would leave the local network.
