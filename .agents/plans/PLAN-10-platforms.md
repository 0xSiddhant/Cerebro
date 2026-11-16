# PLAN-10 — Capture on every Apple platform

## Goal

Make `import Cerebro` and `Cerebro.start()` compile and capture on tvOS, watchOS, macOS and visionOS as they do on iOS, and run the dashboard on the two platforms where UIKit already carries it: Mac Catalyst and visionOS. Today a multiplatform app has to wrap its one Cerebro line in `#if os(iOS)`, which is a code change Cerebro exists to avoid. Pulse covers these platforms with one SwiftUI interface. Cerebro's dashboard is UIKit, chosen after measuring, so a dashboard on each remaining platform is its own piece of work, which PLAN-99 now holds. Until then, a session captured on any platform can be opened in the dashboard on another device, which also lets a tester hand a session to a developer.

## Gate

PLAN-09 merged. Single PR on `plan/10-platforms`. Nothing here needs the Logs tab, so the owner can swap the two plans.

One owner checkpoint comes before the main work: the spike. This plan was drafted where nothing could be compiled, so every platform fact in it comes from reading the code and from memory of the SDKs. The spike is the first task, and the owner sees its answers before the rest starts.

The owner decided the dashboards on 2026-11-14: Mac Catalyst and visionOS in this plan, and tvOS, native macOS and watchOS in PLAN-99 for later.

## Scope

**In:** `CerebroCore`, `CerebroProto` and the `Cerebro` facade on tvOS 16, watchOS 9, macOS 13 and visionOS 1; capture, console output and a session file on all of them; the dashboard on Mac Catalyst and visionOS; sharing a session as a file and opening one from another device; a keyboard shortcut for the dashboard; a release gate that works for macOS signing; all three install options on every platform; CI for each platform; a small multiplatform target in the Example project; documentation.

**Out:**
- The dashboard on tvOS, on native macOS and on watchOS. The owner moved them to PLAN-99.
- Viewing another device's traffic live, such as a watch's on its iPhone or a phone's on a Mac. PLAN-99 holds that idea. Here a session moves between devices as a file, by hand.
- Lower minimum versions. The core uses `OSAllocatedUnfairLock` and `Duration`, which start at the iOS 16 generation on every platform.
- The OSLog view on platforms without a dashboard. It reads the system log live, so it needs a screen.
- Linux.

## Decisions & reasoning

### What it takes, platform by platform

| Platform | Capture and console | Dashboard | What stands in the way |
|---|---|---|---|
| iOS and iPadOS 16 | Today | Today | Nothing |
| iPad apps running on a Mac or a Vision Pro | Today, expected | Today, expected | They run the iOS binary. Never tested |
| Mac Catalyst | This plan | This plan | The release gate, a missing XCFramework slice, no shake, and the Files tab when the app has no sandbox |
| visionOS 1 | This plan | This plan, if the spike's overlay check passes | CoreTelephony, no shake, and whether an overlay window works |
| tvOS 16 | This plan | PLAN-99 | No touch, so no floating button and no shake, and about a dozen UIKit classes the dashboard uses don't exist there |
| macOS 13 | This plan | PLAN-99 | No UIKit, so every view is rewritten in AppKit |
| watchOS 9 | This plan, for `URLSession` | PLAN-99 | No UIKit views, so it needs SwiftUI, which the rules forbid. The OS itself restricts WebSockets and `NWConnection` to a few kinds of app |

The core is close already. It imports Foundation, Network, Compression, Security, CFNetwork, CoreTelephony, ObjectiveC and `os`, and only CoreTelephony is iOS-only, in two files. Every hook is on `URLSession`, `URLSessionConfiguration` or `URLSessionWebSocketTask`, which all five platforms share. The dashboard is the cost: 36 of its files import UIKit, about 4,100 lines of views over 1,771 lines of view models that import only Foundation.

### What a spike must settle first

It runs on a Mac with Xcode, against each platform's simulator, plus a Mac for macOS and Catalyst. Its answers go in `notes.md`.

| Question | Expected | If it goes the other way |
|---|---|---|
| What fails when `CerebroCore` and `CerebroProto` compile for each platform? | CoreTelephony everywhere but iOS, and perhaps the proxy settings call on watchOS | Each failure gets a `#if`. A platform that needs more than that is dropped from this plan, and the owner is told |
| Do the hooks hold on each platform? One request on `URLSession.shared`, one on a custom session, one background transfer, one WebSocket | Yes. CFNetwork is the same underneath | A platform where capture misses traffic says so in the guide, or is dropped |
| Does a development build on tvOS, watchOS and visionOS carry `embedded.mobileprovision` with `get-task-allow`? | Yes | That platform is off unless the developer opts in, and the owner is told |
| On macOS and Catalyst, does a Debug build's own signature carry `com.apple.security.get-task-allow`, signed with a team and signed to run locally, and does a distribution build lack it? | Yes, then no | macOS is off unless the developer opts in, and the owner is told |
| On visionOS, does `PassthroughWindow` show the trigger above the app and pass input through around it, and does the dashboard present over it? | Unknown | visionOS gets capture and console only, and its dashboard joins the others in PLAN-99 |
| On Catalyst, do the trigger's drag, the dashboard, Quick Look and the share popovers work with a pointer? | Yes | Fix what's small. Anything larger is listed for the owner |
| Does `pod lib lint` pass for all five platforms with the CocoaPods on the CI runner? | Yes, for a version that knows visionOS | The pod leaves that platform out, the guide says so, and the owner is told, because the three install options would differ |
| Do ten XCFramework slices build, and what do the release zip and the release job grow to? | They build. Size and time unknown | If either is unreasonable, the owner chooses which slices ship |
| Can a session file be taken off a real Apple TV and a real Watch with Xcode's container download? | Yes for Apple TV, unknown for a Watch | The guide says which devices need a simulator to get the file |
| Does a key command added by hooking `UIApplication` open the dashboard on an iPad with a keyboard, on Catalyst and on visionOS, and does an app's own command with the same keys still win? | Yes | No shortcut ships, and the floating button stays the only automatic trigger there |
| Which simulator runtimes does `macos-26` have? | iOS, tvOS, watchOS and visionOS | A platform with no runtime is built for its device only, and tested by hand |
| With its guard removed, how many errors does the dashboard give on tvOS? | Unknown | Nothing changes here. The number goes in PLAN-99's tvOS row |

### A dashboard where UIKit carries it, and capture everywhere else

On a platform with no dashboard, `Cerebro.start()` still captures, and each request prints to the console at `consoleLevel`, as it does today. That's what a developer running a TV or watch app from Xcode sees first anyway. `Cerebro.present()` does nothing there, and its documentation says so.

That split makes this one plan. The core port is a few guards and a second release-gate check, while every dashboard beyond UIKit's reach is a design of its own.

### On disk, not in memory, where nothing can show it

With no dashboard, nothing reads the stores. Holding 500 requests with their bodies for no reader is a risk on a watch, where memory is tightest. So on those platforms the pipeline prints, appends to the session file, and keeps nothing in memory. It's one flag on `CaptureRuntime`, set by the facade. The plan that brings a platform its dashboard turns it off for that platform.

The session file is what makes those platforms worth more than a console line, as the next decision says. It keeps its 50 MB cap and `previousSessionLimit`, and `isPersistenceEnabled` turns it off as it does on iOS.

At start, Cerebro prints one line there: that it's capturing, that this platform has no dashboard, and where the session file is. A developer who has only ever seen the floating button would otherwise wonder whether anything is happening.

If there's nowhere for data to go, with no dashboard, `consoleLevel` at `.off` and persistence off, capture isn't installed at all. Hooking an app's networking for nothing is a risk with no return.

### A session opens on another device

A session file is already complete, redacted and self-describing: one JSON Lines file with every request, socket frame and, after PLAN-09, log line. The dashboard already shows a saved session read-only. Two small additions join those up:

- **Share Session File**, in the HTTP tab's export menu, shares the running session or a previous one as its file, after the usual warning. HAR stays, for other tools.
- **Open Session File**, in the previous sessions menu, picks a file with the system document picker and shows it in the same read-only screens.

This gives the platforms without a dashboard a full one: run the TV, watch or Mac app, take its session file, and open it in any iOS, Catalyst or visionOS build that has Cerebro. On a Mac and on every simulator the file is on disk already. It also serves iOS alone, because a tester can send a developer the whole session, not a screenshot.

An opened file is read where the picker put it and never copied into the archive. It shows what was saved, redacted by the rules of the build that wrote it. A file is refused, with a message, if it has no header or a newer format version. Lines that don't decode are skipped, as they are today, and the stores' caps apply, so a huge or damaged file can't exhaust memory.

It's a file moved by hand, not a connection between devices, so it stays inside the spec's rule against a companion app. PLAN-99's live stream idea would send these same records over a connection.

### A keyboard shortcut where there's no shake

Catalyst and visionOS have no shake, and an iPad on a keyboard is rarely shaken. Control-Option-Command-C shows or hides the floating trigger, as a shake does. It's added by hooking `UIApplication`'s key commands, the way `ShakeDetector` hooks `UIWindow`, so it needs no code in the app, and `isShakeGestureEnabled` turns it off along with the shake. An app's own command with the same keys wins.

### One guard, written out

The dashboard and the triggers compile only under `#if os(iOS) || os(visionOS)`, which includes Mac Catalyst. The condition is written out in each file, because `#if canImport(UIKit)` is true on tvOS and watchOS, and a custom build flag would have to be defined three times, once per install option.

The facade compiles everywhere. On a platform with no dashboard it holds the runtime and nothing else.

### The release gate on macOS

iOS decides from `embedded.mobileprovision`. A Mac app often has no profile at all: a Debug build signed to run locally doesn't, so today's gate would keep Cerebro off for most Mac developers.

On macOS and Catalyst the gate reads the app's own code signature with `SecCodeCopySigningInformation`, and opens when its entitlements have `com.apple.security.get-task-allow`. Xcode adds that to Debug builds and leaves it out of Developer ID and App Store builds, so it's the same question the iOS profile answers. `allowsDistributionBuilds` still overrides it. macOS has no simulator, so the signature is the only signal.

### Smaller differences

- **No shake** on Catalyst or visionOS, so `isShakeGestureEnabled` does nothing there. The floating button and `Cerebro.present()` remain.
- **CoreTelephony** is guarded. Where it's missing, System Info shows no cellular generation.
- **The Files tab on Catalyst.** An app without the App Sandbox has the user's home folder as its home. Cerebro's data container root is left out unless the home is a sandbox container, so the tab can never delete the user's own files. The app bundle and App Group roots stay.
- **PLAN-09's capture** of standard output and error is the same code on every platform, and its lines go in the session file like everything else.
- **watchOS** allows WebSockets and `NWConnection` only for a few kinds of app. `MonitoredNWConnection` and the hooks compile and work where the OS allows the traffic.

### All three install options, on every platform

- **SPM:** the manifest lists all five platforms. Tools version 5.9 already knows visionOS.
- **CocoaPods:** a deployment target per platform, and `CoreTelephony`, `UIKit` and `QuickLook` named only for the platforms that have them. The `UI` subspec installs everywhere, because the facade lives in it and its files guard themselves.
- **XCFramework:** `Cerebro.xcodeproj` supports every platform, and `Scripts/build-xcframework.sh` archives ten slices instead of two: device and simulator for iOS, tvOS, watchOS and visionOS, plus macOS and Mac Catalyst. Its client check compiles against each slice.

### What CI adds

Tests keep running on the iOS simulator. `CerebroCoreTests` and `CerebroProtoTests` also run on macOS and on a tvOS simulator, which catches a guard that hides too much. watchOS and visionOS are built, not tested, because the hooks are the same code and each extra simulator run costs runner time.

`swift build` and `swift test` on a Mac become a valid check for the core, though not for the dashboard. `AGENTS.md` says so once that's true.

### The other dashboards wait in PLAN-99

tvOS, native macOS and watchOS get capture, the console and a session file here, and no dashboard. PLAN-99 has a row for each with what it needs and how large it is, and tvOS is the first when one is scheduled.

Pulse reaches all of these with one SwiftUI interface, and with a Mac app that reads logs remotely. Cerebro measured SwiftUI and chose UIKit, and its spec rules out a companion app, so it pays for each platform's dashboard separately. Opening a session file on another device is what covers the gap until then.

## Public API

None is added. Three existing ones behave differently by platform, and their documentation says so:

| API | Where it differs |
|---|---|
| `Cerebro.present()` | Does nothing on tvOS, watchOS and native macOS |
| `CerebroConfiguration.isShakeGestureEnabled` | On Mac Catalyst and visionOS there's no shake, so it only governs the keyboard shortcut. On iOS it governs both |
| `CerebroConfiguration.requestLimit`, `socketFrameLimit` | Without a dashboard they only limit the session file, because nothing is kept in memory |

## Task checklist

**Spike (first, and not committed)**
- [ ] Answer every row of "What a spike must settle first"
- [ ] Record the answers in `notes.md` under "What was measured", and show the owner before going on

**Core (`Sources/CerebroCore/`)**
- [ ] Guard CoreTelephony in `Metrics/SystemInfoMonitor.swift` and `Metrics/CellularGeneration.swift`, and whatever else the compile audit finds
- [ ] Add the signature check to `Shared/Configuration/ReleaseGate.swift` for macOS and Catalyst, behind the same `Environment` that tests fill in
- [ ] Add the flag to `CaptureRuntime` that keeps nothing in memory, so the pipeline prints and appends to the session file only
- [ ] Print the start line on platforms without a dashboard, and install nothing when there's nowhere for data to go
- [ ] Let `SessionArchive` copy a session out for sharing, flushed first, and load a file from outside its folder, refusing one with no header or a newer version
- [ ] Leave the data container out of `Files/FileRoot.swift` when a Mac app has no sandbox container

**Facade and dashboard (`Sources/Cerebro/`)**
- [ ] Wrap every file in `Triggers/` and `UI/` in `#if os(iOS) || os(visionOS)`
- [ ] Make `Facade/Cerebro.swift` compile everywhere, with the dashboard only under that guard and the keep-nothing flag set elsewhere
- [ ] Skip the shake hook on Catalyst and visionOS, and add the keyboard shortcut beside it in `Triggers/`
- [ ] Add Share Session File to the HTTP tab's export menu, for the live session and a previous one
- [ ] Add Open Session File to the previous sessions menu, with the refusal messages
- [ ] Fix what the spike found in the dashboard on Catalyst and visionOS

**Distribution**
- [ ] List all five platforms in `Package.swift`
- [ ] Add each platform's deployment target and frameworks to `Cerebro.podspec`
- [ ] Make `Cerebro.xcodeproj` build every platform, and turn Catalyst on
- [ ] Archive ten slices in `Scripts/build-xcframework.sh`, and compile the client against each
- [ ] Add CI jobs: a build for each new platform, core and proto tests on macOS and a tvOS simulator, and `pod lib lint` across platforms

**Tests, documentation and the Example**
- [ ] Unit tests from the test checklist, and guard the dashboard's tests like the dashboard
- [ ] Add a multiplatform smoke target to the Example project that starts Cerebro and makes one request and one WebSocket
- [ ] Add a platform table to `README.md` and `docs/GUIDE.md`: what's captured, where there's a dashboard, and how the gate decides on a Mac
- [ ] Add to the guide how to share a session, where the file is on each platform, how to open it on another device, and the shortcut
- [ ] Update `AGENTS.md` (the description and the commands), `architecture.md` (platforms, the release gate, the modules' frameworks), `tech-stack.md`, `project-structure.md` and `notes.md` (the spec says iOS only)
- [ ] Update the `build-and-test`, `build-xcframework` and `podspec-lint` skills for the new destinations
- [ ] Add what the spike learned to PLAN-99's three dashboard rows, such as the tvOS error count
- [ ] Verify SPM, CocoaPods and XCFramework builds on every platform

## Acceptance criteria

1. A multiplatform app builds for iOS, tvOS, watchOS, macOS and visionOS with `import Cerebro` and `Cerebro.start()` and no `#if`, through SPM, CocoaPods and the XCFrameworks.
2. On each of those platforms, a request on `URLSession.shared` and one on a custom session print a console line in a development build.
3. On Mac Catalyst and visionOS, the floating trigger opens the dashboard and every tab works, apart from what the plan lists as different.
4. On tvOS, watchOS and native macOS, `Cerebro.present()` does nothing, no window is created, nothing is kept in memory, and the session file is written and its path printed at start.
5. A session file from a tvOS, watchOS or macOS run opens in the dashboard on iOS and shows its requests and sockets, read-only.
6. A session can be shared as a file from the dashboard, always after the warning, and opened in another build.
7. A file that isn't a session, has no header or has a newer version is refused with a message, and a damaged or oversized one opens with what could be read, inside the stores' caps.
8. Control-Option-Command-C shows and hides the trigger on an iPad with a keyboard, on Catalyst and on visionOS, unless `isShakeGestureEnabled` is off or the app uses those keys.
9. Cerebro stays off in a distribution build on every platform, including a Developer ID and a Mac App Store build, unless `allowsDistributionBuilds` is set.
10. Cerebro is on in a Mac Debug build signed to run locally.
11. On Catalyst, an app without a sandbox has no data container root in the Files tab.
12. With no dashboard, console output off and persistence off, no hook is installed.
13. Nothing an iOS app already had changes: the same tests pass, and the XCFramework's iOS slices have the same interface.
14. CI builds every platform and runs the core and proto tests on iOS, macOS and tvOS.
15. `README.md` and `docs/GUIDE.md` say what each platform gets, and how a session moves between devices.
16. The `build-and-test` skill passes.

## Test checklist

**Unit: the release gate**
- [ ] A Mac signature with `get-task-allow` set, set to false, and missing
- [ ] No signature at all, and entitlements that can't be read
- [ ] `allowsDistributionBuilds` opens the gate in each of those cases
- [ ] Catalyst uses the signature, not the iOS profile, and iOS still uses the profile
- [ ] A simulator opens the gate on every platform that has one

**Unit: keeping nothing in memory**
- [ ] A request prints, the stores stay empty, and the session file has it
- [ ] A socket's frames and an event stream that ends reach the file, and a stream still open at `stop()` is closed there
- [ ] The file's 50 MB cap and `previousSessionLimit` still hold
- [ ] With persistence off the file isn't written, and what earlier launches saved is removed
- [ ] With console output off and persistence off, no hook is installed, and `start()` then `stop()` is harmless
- [ ] The start line prints once, names the file, and isn't printed with console output off
- [ ] `present()` does nothing before `start()`, after `stop()`, and from a background thread

**Unit: session files across devices**
- [ ] A session written with the keep-nothing flag loads into stores like any other
- [ ] A copy for sharing has everything appended before it was asked for
- [ ] Refused: an empty file, a file with no header, a newer format version, and a file that isn't JSON Lines
- [ ] A last line cut short, and lines of an unknown kind, are skipped
- [ ] A file with more requests than `requestLimit` loads the newest, inside the caps
- [ ] A file with a clear marker shows only what came after it
- [ ] An opened file is never added to the archive's folder or its list of previous sessions

**Unit: the rest**
- [ ] `FileRoot` keeps a home folder that is a sandbox container, leaves out one that isn't, and is unchanged on iOS
- [ ] App Group roots still list on Catalyst without a sandbox
- [ ] The shortcut toggles the trigger, is absent with `isShakeGestureEnabled` off and while Cerebro is off, and `stop()` removes the hook
- [ ] System Info shows no cellular generation, and nothing else changes, without CoreTelephony
- [ ] The existing core and proto tests pass on macOS and tvOS

**Manual**
- [ ] The smoke target on a tvOS, watchOS and visionOS simulator and on a Mac: the console line for each kind of request
- [ ] Take the session file from a tvOS simulator and a Mac run, and open it on an iPhone
- [ ] Share a session from an iPhone by AirDrop and open it in another build
- [ ] A Mac app in Debug, with a development team and signed to run locally: Cerebro is on
- [ ] A Developer ID build: Cerebro is off
- [ ] Catalyst: every tab, the trigger with a pointer, the shortcut, Quick Look, and a share
- [ ] Catalyst: the shortcut while a text field has focus, and in an app that binds the same keys
- [ ] visionOS simulator: the trigger, the dashboard, and the app's own input around the trigger
- [ ] An iPad app running on a Mac, if one is at hand
- [ ] Each of the three install options in a client app on at least macOS and tvOS

## Open questions

1. **Should every XCFramework slice ship?** Recommendation: decide from the spike's zip size and release time. Leaving watchOS out is the first cut if they're too large.
