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
| **Auto-start** | Removes the `Cerebro.start()` line. Spikes showed it works with Objective-C `+load`, but PLAN-01's trade-off kept the line as simpler. It can be added later without breaking anything, since it would only call `start` |
