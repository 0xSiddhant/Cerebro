# PLAN-09 — Logs tab

## Goal

Add a Logs tab that shows what the app itself wrote while it ran: `print`, `debugPrint`, `dump`, anything else on standard output or standard error, `NSLog`, and the app's `os_log` and `Logger` entries. A failing request rarely explains itself, and the line the app logged beside it usually does. Away from Xcode that line is lost today, because iOS sends an app's standard output to `/dev/null` when it's launched from the Home screen. The tab and its system log view need no code change. Capturing standard output and error is opt-in, one argument to `Cerebro.start`, because it redirects state the whole process shares.

## Gate

PLAN-08 merged and `v1.0.1` released. Single PR on `plan/9-logs`.

One owner checkpoint comes before the main work: the spike. This plan was drafted where no simulator could run, so nothing in "What a spike must settle first" is measured yet. The spike is the first task, and the owner sees its answers before the core tasks start, because some of them can change the scope.

The owner has already decided two things, on 2026-11-14: Proto Config moves into the Sockets tab to make room in the bar, and capture of standard output and error is off by default.

## Scope

**In:** capture of standard output and standard error, with everything still reaching Xcode's console; a read of the system log for this process, on demand; a Logs tab with a Console view and an OSLog view, search, a filter, copy, share and clear; console lines in the saved session and in a previous session's view; one setting; Cerebro's own console lines kept out; documentation; all three install options.

**Out:**
- One merged timeline of both views. The first open question says why.
- A logging API of Cerebro's own, such as `Cerebro.log`. It would break zero code change, and every app already has a logger.
- Hooking `os_log` itself. That means rebinding C symbols, which needs a C target and private behaviour.
- Reading a level out of printed text, such as `[ERROR]`.
- Logs of other processes, such as widgets and extensions, and system log entries of earlier launches. iOS gives an app neither.
- Crash reports and MetricKit.
- Linking a log line to the request it was printed beside.
- Streaming logs to a Mac, which the spec rules out with the companion app.

## Decisions & reasoning

### Worth adding, and kept light

The owner's question was whether a lightweight log tab is worth it. It is, for four reasons:

- It fills the gap a network inspector leaves. A 500 shows what failed, and the app's own log line shows why.
- It shows `print` output on a device away from Xcode, which nothing in iOS does. That is the tester's and the QA build's case, which is the case Cerebro exists for.
- Standard output, standard error and the system log can all be reached with public API. The system log costs the app no code, and the other two cost one argument.
- Most of the machinery exists: the ring buffer, batched observers, the session file, the list screens, search, the Body Viewer and sharing.

It also has real costs, and each one has a decision below: redirecting standard output is the most intrusive thing Cerebro does after swizzling, the system log is slow to read and hides private values, and the tab bar is full.

"Light" means a console, not a log analysis tool: lines in order, search, one filter, copy and share. Nothing in "Out" is needed for that.

### What each logging API can support

| The app calls | Where iOS sends it | View | What Cerebro has | Limits |
|---|---|---|---|---|
| `print`, `debugPrint`, `dump` | Standard output | Console | Text, time, stream | No level, file or line. One row per line of output, not per call |
| `printf`, `puts`, `FileHandle.standardOutput` | Standard output | Console | The same | The same |
| `fputs` to `stderr`, `perror`, `FileHandle.standardError`, the Swift runtime's own messages | Standard error | Console | Text, time, stream | The same. A fatal error's message is written an instant before the process dies, so it's usually lost |
| `NSLog`, `CFLog` | The system log always. Standard error too, when no debugger is attached | OSLog always, Console when no debugger is attached | Text, time, level | In Console it carries NSLog's own date and process prefix. It shows in both views, as it does in Terminal and Console.app |
| `os_log`, `Logger` | The system log only | OSLog | Text, time, level, subsystem, category | Private values show as `<private>` without a debugger, and debug and info entries may be missing. Only this launch |
| swift-log, CocoaLumberjack, SwiftyBeaver and others | Whichever of the three their handler writes to | The view for that route | What that route gives | A logger that only writes a file shows in the Files tab instead |
| Anything written before `Cerebro.start()` | | OSLog only | | Console starts at `start`. The system log has the whole launch |
| A widget's or an extension's logs | Another process | Neither | | Out of reach |

Console rows need `isLogCaptureEnabled`. OSLog rows need nothing.

The NSLog row comes from the open-source CoreFoundation, where [`also_do_stderr`](https://github.com/apple/swift-corelibs-foundation/blob/main/Sources/CoreFoundation/CFUtilities.c) defers to the system log under a debugger and otherwise writes to a standard error that is a pipe. The `Logger` row comes from [Apple's answer](https://developer.apple.com/forums/thread/739047) that `Logger` never writes to standard output or error unless Xcode's `OS_ACTIVITY_DT_MODE` is set. The spike confirms both on a device, because the CoreFoundation that ships isn't the open-source one.

### What a spike must settle first

It runs in the Example app, on a simulator and on a real device, launched from Xcode and from the Home screen. It stays out of the repository, and its numbers go in `notes.md`.

| Question | Expected | If it goes the other way |
|---|---|---|
| After `dup2` onto descriptor 1 and `setvbuf(stdout, nil, _IOLBF, 0)`, does each `print` arrive at once, however the app was launched? | Yes | Try unbuffered. If lines still arrive late, the owner is told before capture is built |
| Does Xcode's console still show every line, in order within each stream? | Yes, through the copy to the original descriptor | The owner is told, and the guide says what Xcode loses while capture is on |
| Does referencing `stdout` compile under strict concurrency with warnings as errors, in all three builds? | Unknown. It's an imported global variable | Look the stream up with `dlsym`, at that one C boundary |
| What does a captured `print` cost? 100,000 calls in a Release build, from Xcode and from the Home screen, with and without capture | No slower than the same build under Xcode, where standard output is already line-buffered | The guide gives the measured cost beside the setting. Capture is opt-in either way |
| Does a burst bigger than the pipe's buffer stall the app? 1 MB printed in a loop | No. The reader only reads, copies and queues | Raise the reader's priority, and record the stall |
| Does `NSLog` reach the pipe on standard error without a debugger, and not with one? | Yes, then no | Only the table above and the guide change |
| Does `OSLogStore(scope: .currentProcessIdentifier)` work on a device with no entitlement, and return this launch from its start? | Yes | With no OSLog view, the tab is Console only, and the owner is told |
| How long does it take to read the newest 2,000 entries after 10,000 were logged? Are `position` and `.reverse` honoured? Does a predicate on `subsystem` work? | Unknown. Reports say it's slow, and that `position` has been ignored on iOS | Over about 250 ms, the view only reads when it opens and on pull to refresh. A missing predicate means filtering in memory |
| Without a debugger, are debug and info entries there, and are private strings `<private>`? | Missing, and yes | Only the guide's wording changes |
| After `stop()` and a second `start()`, is everything restored and captured again, with no `SIGPIPE`? | Yes | Fix it before any other task. A broken restore can kill the host app |

### Two sources, two views

Standard output and error are captured: they pass through the pipeline into a store, like traffic. The system log is not captured. iOS already stores it, so Cerebro reads it when the view is on screen and keeps no copy, the way the Files tab reads a folder.

A segmented control in the title switches between Console and OSLog, as System Info switches pages. The tab opens on Console while capture is on, and on OSLog while it's off. The two aren't merged into one timeline. Their timestamps come from different clocks, `NSLog` would appear twice, and the system log is too slow to read continuously, so a merged list would have gaps that look like silence. Each view shows one system honestly.

### Standard output and error: a pipe, and a copy to where it was going

For each of the two descriptors, `StandardStreamCapture` keeps a duplicate of the original, points the descriptor at a pipe with `dup2`, and reads the pipe on its own serial queue. Each chunk it reads is first written to the original descriptor, so Xcode's console and anything else reading the app's output still get all of it. Then the chunk is queued for the pipeline.

Host app safety rules, because this touches process-wide state:

- The reader never does more than read, copy and queue. A full pipe blocks the app's `print`, so the reader must never wait on anything else.
- The pipe is never made non-blocking. That would drop the app's output from Xcode as well.
- `stop()` restores the descriptors before it closes the pipes, and the write ends are set to never raise `SIGPIPE`.
- A descriptor is restored only if it still points at Cerebro's pipe. Another tool may have redirected it since.
- Standard output is set to line buffering. Under Xcode it already is, because it's a terminal. Without that, a pipe makes it fully buffered and lines arrive in blocks, late.
- Nothing is redirected unless `isLogCaptureEnabled` is set, or while Cerebro is off in a distribution build.

`StandardStreamCapture` takes the descriptor it redirects as an argument. Tests hand it a pipe of their own, because redirecting the test runner's real output would catch every other test's lines.

Two things change for the app while capture is on, and the guide says so: `isatty` is false for both streams, and standard output is line-buffered even from the Home screen.

### Rows are lines, not print calls

A pipe carries bytes, so nothing marks where one `print` ended. Guessing from how the bytes arrive would group lines differently on a busy device. One row per line is what Xcode's console and a terminal show, and the list is styled as a console, so a multi-line dump reads as it would there.

`LogLineAssembler` splits chunks at newlines and holds an unfinished line until the rest arrives or 250 ms pass. A line over 8 KB is cut and marked. A line that isn't UTF-8 is replaced by a note with its byte count. A line's time is when Cerebro read it, which is normally within a millisecond of the call, and lines read together share a time.

### Redaction: a line that names a redacted field is withheld

Free text can't be redacted field by field. Bodies already have a rule for that: text that names a configured key is withheld. Lines get the same rule, widened to every name in `RedactionRules`: headers, JSON keys and query parameters. An app that prints its request headers would otherwise put the `Authorization` value on disk after the developer asked for it to be redacted.

A withheld line keeps its time and stream, and says it was withheld. The cost is false positives: with `Authorization` configured, "Authorization failed" is withheld too. Privacy wins that trade, as it does for bodies, and with no rules configured nothing is withheld. The check runs in the pipeline before the store, and on system log entries before they reach the view, so the dashboard, the session file and a share never hold the raw line.

The copy that goes to Xcode's console isn't changed. That is the app's own output on its own descriptor, not something Cerebro stored.

### Storage and caps

`LogStore` is an actor like the other two stores: a ring buffer of 5,000 lines, capped at 2 MB of text as well, publishing to readers at most once per 250 ms and never while nobody reads. A `CaptureBacklog` of 1 MB sits between the reader and the pipeline. A chunk that doesn't fit is still copied to Xcode but not stored, and the store counts the bytes dropped so the screen can say so.

Lines go to the session file as one record per chunk, not one per line. A chatty app prints thousands of lines a second, and a disk write for each would be the most expensive thing Cerebro does. A crash still loses only what was in flight. The file's existing 50 MB limit covers them. Clear writes a marker line, as it does for HTTP, so cleared lines don't come back after a relaunch.

The record is a new case of `SessionRecord`. A reader skips a line it can't decode, so a file from 1.0 loads with no lines, and the format version stays 1.

Output written just before a crash can be lost, because it's still in the pipe when the process dies. The guide says so, and that the system log on a Mac is the place to look for those lines.

### The OSLog view: read on demand, never stored

`SystemLogReader` opens `OSLogStore(scope: .currentProcessIdentifier)`, which iOS 15 added, and maps each `OSLogEntryLog` to a `Sendable` value inside the task that read it. It reads the newest 2,000 entries when the view appears, then every 2 seconds from the newest one it has, one read at a time, and stops when the view goes away. Nothing reads the system log while the dashboard is closed.

The app runs inside system frameworks that log heavily, so entries whose subsystem starts with `com.apple.` are hidden unless the filter turns them on. `NSLog`, which has no subsystem, always shows.

Entries aren't written to the session file. They'd only be the ones read while the view happened to be open, which would look complete and not be. A previous session therefore shows Console lines only.

### Cerebro's own lines stay out

`ConsoleLogger` prints one line per request, and at `.full` every body. Captured, those would fill the 5,000 lines with what the HTTP tab already shows, and copy bodies into a second store. So Cerebro writes its own lines straight to the original descriptor: one `ConsoleOutput` value that `ConsoleLogger` and `FileRoot` both use, which falls back to `print` while capture is off. They still reach Xcode and never enter the pipe.

### Logs takes Proto Config's place in the bar

The bar holds five tabs before an iPhone adds More, and all five are taken when an app has proto rules. More is not acceptable: it wraps the sixth tab in its own navigation controller and adds an Edit button.

The owner's decision is that Proto Config stops being a tab and opens from the Sockets tab only. The Sockets list gets a bar button with the `curlybraces` symbol, shown when there are rules, which pushes the same `ProtoConfigViewController` unchanged. A previous session's socket list doesn't have it, because the rules belong to the running app. The bar becomes HTTP, Sockets, Logs, Files, System Info, always five or fewer.

The screen still lists every rule, including ones that only match HTTP bodies, because it's now the only way in. The guide says where it went.

Rejected: a row on System Info, which this plan first recommended and the owner passed over for Sockets; merging HTTP and Sockets into one tab, which redesigns the two most used screens; and a custom scrolling bar, which replaces a system control with one to maintain.

The tab is called Logs and uses the `terminal` symbol. The spec's name for the request detail screen is Log Inspector, so every new type starts with `LogLine`, `LogList`, `LogStore`, `StandardStream` or `SystemLog`, and none with `LogInspector`.

### The screen

- One list for both views, in a monospaced font, oldest at the top and newest at the bottom, with the time beside each line. Standard error and the error and fault levels are tinted, with colours from `DashboardTheme`.
- It follows new lines while it's scrolled to the bottom. Scrolling up stops that, and a button jumps back to the newest line.
- Search matches text, without regard to case. The scope bar is All, Output and Errors for Console, and All and Errors for OSLog. OSLog rows also show the level, and the subsystem and category when there are any.
- A row shows up to four lines of a long line. Tapping one opens the whole line in the Body Viewer, which pretty-prints it when it's JSON. The context menu copies it.
- Share sends what the view and its filter show as a text file, after the same warning as other captured data. Clear empties Console after asking. The system log can't be cleared, so OSLog has no Clear.
- The previous sessions button opens a saved session's Console lines, read-only, like the HTTP and Sockets tabs.
- The trigger's badge still counts requests only.

### One setting, off by default

`isLogCaptureEnabled` turns on the capture of standard output and error. It defaults to `false`, which is the owner's decision: redirecting two descriptors the whole process shares is the most intrusive thing Cerebro does, so a developer asks for it. `Cerebro.start()` still needs no arguments.

The setting covers capture only. The Logs tab is always there, because the OSLog view redirects nothing and reads only while it's on screen. While capture is off, the Console view is an empty state that names the setting, so the feature can be found from inside the app.

This is the one place the tab needs code, so it joins the table of those places in `architecture.md`.

The caps are fixed. The second open question asks whether the line count should be a setting.

## Public API

| API | Purpose | Notes |
|---|---|---|
| `CerebroConfiguration.isLogCaptureEnabled` | Captures standard output and error for the Console view | Defaults to `false`. Set it to see `print` output |

Nothing else changes for the host app, and no code is needed for the tab or its OSLog view.

## Task checklist

**Spike (first, and not committed)**
- [ ] Answer every row of "What a spike must settle first" in the Example app, on a simulator and a real device, from Xcode and from the Home screen
- [ ] Record the numbers in `notes.md` under "What was measured", and show the owner before going on

**Core (`Sources/CerebroCore/Log/`, in `Capture/`, `Pipeline/`, `Store/`, `Models/` and `System/`)**
- [ ] Add `LogLine` with an ID, date, stream, text, and whether it was cut or withheld, `public`, `Codable` and `Sendable`
- [ ] Add `StandardStreamCapture` for one descriptor: duplicate, pipe, `dup2`, line buffering for standard output, a reader that copies to the original and then queues, and a restore that only undoes its own redirect
- [ ] Add `LogLineAssembler`: split at newlines, hold a partial line for 250 ms, cut at 8 KB, and note a line that isn't UTF-8
- [ ] Add one check to `Redactor` for text that names any configured header, JSON key or query parameter, and withhold those lines in the pipeline
- [ ] Add `LogStore`: 5,000 lines and 2 MB, a dropped-bytes count, batched updates, clear, and the journal
- [ ] Add `SystemLogReader` and `SystemLogEntry`: the newest 2,000 entries, entries after a date, the `com.apple.` filter, and the same withheld check
- [ ] Add `ConsoleOutput`, and route `ConsoleLogger` and `FileRoot` through it
- [ ] Wire capture into `CaptureRuntime` behind a 1 MB `CaptureBacklog`, started in `start()` only when `isLogCaptureEnabled` is set, and restored in `stop()`
- [ ] Add the log and cleared records to `SessionRecord`, written one per chunk, and a `LogStore` to `StoredSession`
- [ ] Add `isLogCaptureEnabled` to `CerebroConfiguration`, defaulting to `false`
- [ ] Keep every new type and file name unique across `Sources/CerebroCore` and `Sources/Cerebro`

**Dashboard (`Sources/Cerebro/UI/Logs/`, `DashboardTabBarController.swift`, `UI/SocketList/`, `Facade/Cerebro.swift`)**
- [ ] Add the Logs tab after Sockets, and pass the store through `DashboardSources`, or `nil` while capture is off
- [ ] Take Proto Config out of the bar, and add its button to the live Sockets list when there are rules
- [ ] `LogListViewController`, `LogListViewModel` and `LogLineCell`: the Console and OSLog switch, the rows, tinting, and following the newest line
- [ ] Search and the scope bar for each view, and the system frameworks filter for OSLog
- [ ] Tap to open a line in the Body Viewer, and Copy in the context menu
- [ ] Share through `CapturedContentSharing`, and Clear with a confirmation, for Console only
- [ ] Read the system log only while the OSLog view is on screen, with a loading state and pull to refresh
- [ ] The previous sessions button, and a read-only list for a saved session
- [ ] Empty states that say what each view shows, that Console starts at `Cerebro.start()`, and while capture is off, that `isLogCaptureEnabled` turns it on

**Tests, documentation, and distribution**
- [ ] Unit and view-model tests from the test checklist
- [ ] Add a Logs sample to the Example app that calls each API in the support table, and prints a burst
- [ ] Add `OSLog` to the podspec's `Core` frameworks
- [ ] Add a Logs section to `docs/GUIDE.md`: the support table, both views, the limits, redaction, the setting, and where lines from just before a crash are
- [ ] Add to the guide's "What changes while Cerebro captures": standard output and error are pipes, `isatty` is false, and standard output is line-buffered
- [ ] Add the tab to the `README.md` features and a screenshot, and say in the guide and its troubleshooting table that Proto Config opens from the Sockets tab
- [ ] Update `AGENTS.md`'s opening description, `architecture.md` (the diagram, the capture sources, the tab list, the `OSLog` dependency, and the setting in "Where an app still writes code"), `project-structure.md`, `tech-stack.md` and `notes.md` (the scope, the tab bar, and what the spike measured)
- [ ] Confirm `PrivacyInfo.xcprivacy` needs no new reason, since neither the descriptors nor `OSLogStore` are on Apple's required-reason list
- [ ] Verify SPM, CocoaPods and XCFramework builds

## Acceptance criteria

1. With no code change, the dashboard has a Logs tab that shows the OSLog view, and its Console view says how to turn capture on.
2. With `isLogCaptureEnabled` set, a line the app prints after `Cerebro.start()` with `print`, `debugPrint`, `dump` or a write to standard error shows in Console within a second, launched from Xcode or from the Home screen.
3. With capture on, everything the app writes still reaches Xcode's console, in order within each stream.
4. OSLog shows the newest 2,000 `NSLog`, `os_log` and `Logger` entries the system log holds for this launch, with their level, subsystem and category, and system framework entries are hidden until the filter shows them.
5. The bar never shows more than five tabs or More, and the proto rules open from the Sockets tab when there are any.
6. With redaction rules configured, a line that names a redacted field is withheld in the dashboard, the session file and a share.
7. Cerebro's own console lines still reach Xcode and never show in the tab.
8. The store never holds more than 5,000 lines or 2 MB. Output that arrives faster than it can be kept is dropped from the tab, never from Xcode, and the tab says so.
9. A 1 MB burst of output doesn't stall the app, and the guide gives what a captured `print` costs, as the spike measured it.
10. Search, the scope bar, copy, share and clear work, and share always warns first.
11. After a relaunch, the previous session shows its Console lines, without the ones cleared before it ended.
12. After `Cerebro.stop()`, both descriptors are what they were before `start`, and a second `start` captures again.
13. Without `isLogCaptureEnabled`, nothing is redirected. While Cerebro is off, the system log is never opened either, and no tab exists.
14. `docs/GUIDE.md` and `README.md` describe the tab, what each logging API can show, and the limits.
15. The feature works the same through SPM, CocoaPods and XCFrameworks, and the `build-and-test` skill passes.

## Test checklist

**Unit, with pipes the test owns in place of the real descriptors**
- [ ] `StandardStreamCapture`: bytes written to the redirected descriptor reach the handler and the original, in order
- [ ] Restore puts the original back, leaves a descriptor someone else redirected alone, and a write after it can't raise `SIGPIPE`
- [ ] `LogLineAssembler`: several lines in one chunk, a line across two chunks, a partial line flushed after the delay, the 8 KB cut, and bytes that aren't UTF-8
- [ ] A line that names a configured header, JSON key or query parameter is withheld, and nothing is withheld with no rules
- [ ] `LogStore`: the line cap, the byte cap, the dropped-bytes count, clear, batched updates, and no publishing with no reader
- [ ] The session file: lines round-trip, a clear marker removes the lines before it, a 1.0 file loads with no lines, and a chunk is one record
- [ ] `ConsoleLogger`'s output goes to the original descriptor and never to the store
- [ ] By default, and with the release gate closed, nothing is redirected

**Integration, on the simulator**
- [ ] `SystemLogReader` reads back a unique message logged with `Logger`, with its level, subsystem and category, and hides a `com.apple.` entry by default

**View models**
- [ ] Rows for both views, each scope, and search
- [ ] Following stops when scrolled up and resumes at the bottom
- [ ] The shared text is what the view and its filter show
- [ ] Which tabs show, in order, with and without files, and that proto rules never add one
- [ ] The Sockets list offers Proto Config only with rules, and never on a previous session
- [ ] The tab opens on Console with capture on, and on OSLog with it off

**Manual**
- [ ] On a real device from the Home screen: each API in the support table lands where the table says
- [ ] Under Xcode: the console shows the same lines with capture on and off
- [ ] Print 100,000 lines with the tab open and scroll it
- [ ] Crash the app after printing, relaunch, and see which lines the previous session has
- [ ] An app with swift-log or CocoaLumberjack shows its lines
- [ ] Exercise the tab through SPM, CocoaPods and XCFramework client builds

## Open questions

1. **Should the two views become one timeline later?** Recommendation: not in this plan. It needs the system log read continuously, and the spike's read time decides whether that's affordable.
2. **Should the 5,000-line cap be a setting, like `requestLimit`?** Recommendation: no, until someone asks. A fixed cap keeps `Cerebro.start()` simple, and the byte cap is what protects memory.
3. **Should system log entries be saved with the session?** Recommendation: no. A single read as the app goes to the background would catch most of a session, but not a crash, which is when a saved log matters most.
