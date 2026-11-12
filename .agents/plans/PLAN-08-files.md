# PLAN-08 — Sandbox file browser

## Goal

Add a Files tab that shows the app's sandbox as folders and files, previews any file, and lets a developer copy, move, rename, delete, share and import files without leaving the app. Bugs that live in what an app wrote to disk, such as a stale cache, a bad preferences file or a database that should have been removed, are as hard to see on a device as network traffic is, and today they need Xcode's container download or a simulator path.

## Gate

PLAN-06 merged. Single PR on `plan/8-files`. The owner answers the open questions before the first commit.

## Scope

**In:** a Files tab, second to last; the data container and the app bundle as browsable roots; folder listing with sort, search and live refresh; previews through Quick Look, with Cerebro's Body Viewer for what Quick Look shows badly; copy, move, rename, duplicate, delete, new folder, share and import, one at a time or for a selection; a file info page; folder sizes; a setting to turn the tab off; documentation; all three install options.

**Out:** editing a file's contents; a SQLite table browser and a `UserDefaults` editor, which are their own plans; the Keychain, which isn't files; iCloud containers; thumbnails in the list; a "recently changed" view (see Open questions); a Mac companion app, which the spec rules out.

## Decisions & reasoning

### What a spike settled first

A spike in the Example app, on an iPhone 17 simulator, settled what the design leans on. It isn't in the repository.

| Question | Answer | What it decides |
|---|---|---|
| Does `QLPreviewController` work inside Cerebro's own window? | Yes, both presented and pushed. Text, JSON and an image rendered. The first preview took more than 4 seconds to appear on the simulator | Quick Look is usable, and the preview needs a loading state |
| What does Quick Look do with a binary plist? | Shows the raw bytes as text, starting `bplist00` | Cerebro decodes plists itself |
| What does it do with JSON? | Shows it unformatted on one line | JSON opens in the Body Viewer |
| Is `QLPreviewController.canPreview` a good guide? | No. It's `false` for a SQLite file and a file with no extension, and `true` for a `.bin` and a binary plist it can't show properly | Routing goes by type, not by `canPreview` alone |
| Can the app reach outside its container? | On a simulator, yes: the folder above the container listed. The app bundle is also writable there | Every path is checked against its root, and the bundle is read-only everywhere |
| Can iOS zip a folder for sharing? | Yes. `NSFileCoordinator` with `.forUploading` made a `.zip` | Sharing a folder needs no zip code of Cerebro's own |
| Does a folder watcher fire when a file is added? | Yes, a `DispatchSource` on the folder. A change to a file's contents wasn't tried | Live refresh without polling, for entries coming and going |

If Quick Look misbehaves on a real device, the fallback is the Body Viewer for text and hex and a plain image view, and every other type gets Share only.

### A fifth tab, before System Info

The tab is called Files, uses the `folder` symbol, and sits before System Info: HTTP, Sockets, Proto Config when there are rules, Files, System Info. That is five tabs at most, which is what an iPhone's tab bar shows before it adds More. A sixth tab would need the bar rethought, and this plan says so in the notes.

### File code in the core, Quick Look in the dashboard

Listing, attributes, sizes, search and file operations go in `Sources/CerebroCore/Files/`. They use Foundation only, so they're tested without UIKit, like the rest of the core. Screens and Quick Look go in `Sources/Cerebro/UI/Files/`. Files aren't traffic, so they don't pass through capture, the pipeline or a store. They plug into the dashboard from the side, as network info does.

There is no store and no cache of the tree. Each folder is read when it's opened, so nothing can go stale and nothing needs a cap on memory beyond the one listing on screen.

### Two roots, and nothing outside them

The tab opens on a list of locations: the data container, which holds `Documents`, `Library`, `tmp` and `SystemData`, and the app bundle. Each shows its size. Opening one pushes its folders, one screen per level, with the path's parents in the title's menu to jump back up.

Every operation resolves its paths, symlinks included, and refuses one that ends outside its root. A real device's sandbox already stops that, but the spike showed a simulator doesn't, and a debugging tool must not be able to delete files on the developer's Mac. A symlink is listed as a link with its target, and is never followed out of its root.

The app bundle is read-only everywhere. On a device it's signed and can't change. On a simulator it can, so Cerebro refuses anyway, to behave the same in both and never corrupt the installed app.

Hidden files are listed like any other, because a debugging tool that hides files is misleading.

### Everything off the main thread, and bounded

Listing a folder, measuring sizes, searching and every file operation run on a background task. A listing reads names and attributes in one batched call.

A folder's size and item count are worked out after its row appears, and stop at 20,000 items, after which the row says "more than". Leaving the screen cancels the work. A search through subfolders stops at 50,000 items visited or 500 results, says so if it stopped early, and is cancelled by the next keystroke.

The open folder is watched with a `DispatchSource`, so a file the app adds, removes or renames shows up without a manual refresh. Changes within 250 ms arrive as one reload, as the stores' updates do. The watcher sees the folder's entries change, not a file's contents, so a file that only grew keeps its old size on screen until the folder is reopened or pulled down to refresh.

### Preview by type

Tapping a file opens the viewer that suits it:

| File | Opens in | Why |
|---|---|---|
| Property list, binary or XML, by extension or by its first bytes | Body Viewer, converted to JSON, with the tree view | Quick Look shows a binary plist as raw bytes. This also makes `Library/Preferences` readable, which is where `UserDefaults` lives |
| JSON | Body Viewer, pretty-printed | Quick Look shows it on one line |
| Images, PDF, audio, video, HTML, RTF, CSV, office and iWork documents, plain text | Quick Look, pushed with the tab bar hidden | It renders them properly, with zoom, paging and text search |
| Anything else: SQLite, files with no extension, unknown types | Body Viewer, as text if the bytes are UTF-8 and as hex if not | Quick Look shows a blank icon for these |

The Body Viewer reads at most `bodyLimit` bytes and says when a file was cut off, reusing the wording it has for a truncated body. A plist over `bodyLimit` isn't converted and opens as hex. A plist value JSON can't hold is written as text: a date in ISO 8601, and data as Base64.

A guess can be wrong, so the context menu also offers Open in Quick Look and Open as Text or Hex for every file.

Quick Look's editing and markup stay off, since this plan doesn't edit files.

### Actions, and what guards them

| Action | On | Notes |
|---|---|---|
| Rename | One item | The name can't be empty, `.` or `..`, or hold a `/` |
| Duplicate | One item | Makes `name 2.ext` beside it |
| Copy to, Move to | One item or a selection | A folder picker limited to writable folders in the same root |
| Delete | One item or a selection | Asks first, and says how many items a folder holds |
| Delete Contents | A folder | Empties it and keeps the folder, for `Caches` and `tmp`. Asks first |
| New Folder | The open folder | |
| Share | One item or a selection | Through the share sheet, after the privacy warning. A folder is zipped by the system first |
| Import | The open folder | Picks a file with the system document picker and copies it in, to seed test data |
| Info | One item | Path, size, created and modified dates, type, permissions, data protection class, whether it's excluded from backup, a link's target, and a folder's item count |
| Copy Path | One item | The full path, and the path inside the container |

A name that's already taken never overwrites: a copy, a move or an import gets `name 2.ext`, and a rename is refused with a message. Nothing here can be undone, which is why the two deletes ask.

An action that doesn't apply isn't shown. The bundle's items offer only Preview, Share, Info and Copy Path, and an item the process can't write offers the same.

Cerebro's own folder, `Library/Caches/Cerebro`, gets no special case. Deleting it loses the saved sessions and nothing else, and the HTTP list already has Clear.

A failure shows the system's error text and changes nothing else. No path crashes the app.

### Files aren't redacted

Redaction rules name headers, JSON keys and query parameters in traffic. They don't apply to files, which the tab shows exactly as they are on disk. Nothing is copied, stored or sent anywhere by browsing. A file leaves the device only when the developer shares it, after the same warning as captured data, reworded for files.

### The app doesn't know its files changed

Cerebro changes files, not the app's memory. An app that has a database open, or `UserDefaults` it has already read, keeps its own view until it reads again or relaunches. The guide says so, and says to relaunch after changing anything the app holds open.

### One setting, on by default

`isFileBrowserEnabled` turns the tab off. The default is on, so `Cerebro.start()` still needs no arguments. It exists for builds given to testers with `allowsDistributionBuilds`, where a developer may want traffic inspection without handing over the power to delete the app's data.

## Public API

| API | Purpose | Notes |
|---|---|---|
| `CerebroConfiguration.isFileBrowserEnabled` | Shows or hides the Files tab | Defaults to `true`. No app has to set it |

Nothing else changes for the host app, and no code is needed to use the tab.

## Task checklist

**Core (`Sources/CerebroCore/Files/`)**
- [ ] Add the roots: the data container and the app bundle, with the bundle read-only
- [ ] Add a file entry model with name, kind, size, dates, type, link target and whether it's writable
- [ ] List a folder in one batched read, off the main thread, with sorting by name, date or size, folders first
- [ ] Measure a folder's size and item count, cancellable, stopping at 20,000 items
- [ ] Search by name in a folder and through its subfolders, cancellable, stopping at 50,000 items visited or 500 results
- [ ] Add rename, duplicate, copy, move, delete, delete contents and new folder, each checking that every path stays inside its root after resolving symlinks
- [ ] Never overwrite: number the name on copy, move and import, and refuse a rename to a taken name
- [ ] Classify a file by extension and first bytes, read at most `bodyLimit` bytes, and convert a plist to JSON
- [ ] Watch a folder for added, removed and renamed entries and report them at most once per 250 ms
- [ ] Make what the dashboard uses `public` with doc comments, and keep every new type and file name unique across `Sources/CerebroCore` and `Sources/Cerebro`
- [ ] Add `isFileBrowserEnabled` to `CerebroConfiguration`

**Dashboard (`Sources/Cerebro/UI/Files/`, `Sources/Cerebro/UI/DashboardTabBarController.swift`, `Sources/Cerebro/Facade/Cerebro.swift`)**
- [ ] Add the Files tab before System Info, only when `isFileBrowserEnabled` is set, and pass `bodyLimit` and the setting through `DashboardSources`
- [ ] Locations screen with each root's size
- [ ] Folder screen with an icon, name, size and modified date per row, the path's parents in the title menu, a sort menu, pull to refresh, and search with This Folder and Subfolders scopes
- [ ] Route a tap to Quick Look or the Body Viewer by type, with a loading state while Quick Look prepares, and offer both viewers in the context menu
- [ ] Context menu and swipe actions per item, showing only the actions that apply
- [ ] Selection mode with Delete, Copy to, Move to and Share for the selected items
- [ ] Folder picker for Copy to and Move to
- [ ] Info screen
- [ ] Import through the system document picker. If it can't be presented from Cerebro's window, leave import out and say so in the PR
- [ ] Share a file or a selection through the share sheet after the warning, zipping a folder with `NSFileCoordinator`, and reuse `CapturedContentSharing` with wording for files
- [ ] Confirm both deletes, and show the system's error text when an action fails

**Tests, documentation, and distribution**
- [ ] Unit and view-model tests from the test checklist
- [ ] Add a sample to the Example app that writes a few files: JSON, a plist, an image and a file with no extension
- [ ] Add `QuickLook` and `UniformTypeIdentifiers` to the podspec's `UI` subspec
- [ ] Add a Files section to `docs/GUIDE.md`: what the tab shows, each action, how previews are chosen, the limits, that files aren't redacted, that the app must be relaunched to see some changes, and the new setting
- [ ] Add the Files tab to the `README.md` intro and status line, and a screenshot
- [ ] Update `architecture.md` (the side input, the tab list and the `Cerebro` module's frameworks), `project-structure.md`, `tech-stack.md` and `notes.md`
- [ ] Verify SPM, CocoaPods and XCFramework builds

## Acceptance criteria

1. With no code change, the dashboard has a Files tab between the other tabs and System Info, and it's absent when `isFileBrowserEnabled` is `false`.
2. The tab shows the data container and the app bundle, and every folder and file beneath them, hidden ones included, one level per screen.
3. Tapping a file previews it: plists and JSON are readable, images and documents open in Quick Look, and any other file opens as text or hex. A file over `bodyLimit` opens cut off and says so.
4. Rename, duplicate, copy, move, delete, delete contents and new folder work in the data container, and a selection can be deleted, copied, moved or shared together.
5. No action overwrites an existing item, and both deletes ask first.
6. Nothing in the app bundle can be changed, on a device or a simulator, and no action can read or change a path outside its root, including through a symlink or a name such as `..`.
7. A file or a zipped folder can be shared, always after the warning, and a file can be imported into the open folder.
8. A file the app adds, removes or renames while its folder is open shows without a manual refresh, and pulling down refreshes sizes and dates.
9. Listing, sizes, search and every action run off the main thread. A folder of 10,000 files opens without blocking the UI, and size and search stop at their limits and say so.
10. A failed action shows why and leaves the files as they were. No path crashes the app.
11. While Cerebro is off, no file is read and no tab exists.
12. `docs/GUIDE.md` and `README.md` describe the tab, its limits and the setting.
13. The feature works the same through SPM, CocoaPods and XCFrameworks, and the `build-and-test` skill passes.

## Test checklist

**Unit, against a temporary folder as the root**
- [ ] Listing: names, kinds, sizes, dates, hidden files, a symlink and its target, and each sort order with folders first
- [ ] Folder size and item count, the 20,000-item stop, and cancellation
- [ ] Search in a folder and through subfolders, both stops, and cancellation
- [ ] Each operation's result on disk, and that a failure leaves the files unchanged
- [ ] Containment: a symlink that points outside, a rename to `..` or a name with `/`, and a move to a folder outside the root are all refused
- [ ] Name collisions: `name 2.ext`, then `name 3.ext`, and a refused rename
- [ ] A read-only root refuses every change
- [ ] Classification by extension and by first bytes, the read cap, and plist to JSON with a date and data value
- [ ] The watcher reports an added, removed and renamed entry, and batches a burst

**View models**
- [ ] Rows, sort and search results for a listing
- [ ] Which actions each kind of item offers, including a bundle item and an unwritable one
- [ ] Which viewer each type opens in
- [ ] Selection, and what the selection actions apply to
- [ ] The tab is present or absent by the setting, and sits before System Info

**Manual**
- [ ] On a real device: Quick Look for an image, a PDF, a video and a text file, and the first preview's delay
- [ ] On a real device: the app bundle refuses changes, and a file with complete data protection opens while the device is unlocked
- [ ] Share a file and a folder by AirDrop, and import a file from the Files app
- [ ] Open a folder of 10,000 files and scroll it
- [ ] Change the app's preferences file, relaunch, and see the app read the change
- [ ] Exercise the tab through SPM, CocoaPods and XCFramework client builds

## Open questions

1. **Quick Look has its own share button, which skips Cerebro's warning.** The coding rules say an export shows a warning first, and no public API removes that button. Recommendation: accept it and record it in `notes.md`, because the developer is already reading the file and chose a system button. The alternative is to drop Quick Look and show only text, hex and images, which loses PDF, media and documents.
2. **App Group containers.** A widget or an extension shares files with the app there, but iOS has no public way to list an app's groups, so the developer would have to name them in a second setting, such as `appGroupIdentifiers`. Recommendation: include it in this plan, because it's one setting and one more root, and shared containers are among the hardest to inspect.
3. **A "recently changed" view,** listing the files modified since launch across the data container. It answers "what did my app just write?", but it needs a scan of the whole container when opened. Recommendation: leave it for a follow-up, and see first whether search and the date sort cover it.
4. **Before or after `v1.0.0`?** The plan adds a setting and two system frameworks, none of them breaking. Recommendation: don't tie it to the release. Merge it when it's ready, on either side of 1.0.
