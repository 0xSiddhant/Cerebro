# Cerebro guide

Installing and starting Cerebro is in the [README](../README.md). This guide covers everything after that.

- [Features](#features)
- [Configuration](#configuration)
  - [Redaction](#redaction)
- [Traffic that needs code](#traffic-that-needs-code)
- [Protobuf decoding](#protobuf-decoding)
- [Server-Sent Events](#server-sent-events)
- [Background transfers](#background-transfers)
- [System Info](#system-info)
- [Previous sessions](#previous-sessions)
- [Export](#export)
- [Files](#files)
- [When Cerebro runs](#when-cerebro-runs)
- [What changes while Cerebro captures](#what-changes-while-cerebro-captures)
- [What Cerebro can't capture](#what-cerebro-cant-capture)
- [Troubleshooting](#troubleshooting)

## Features

**Capture**

- `URLSession` traffic with no code change, including `URLSession.shared` and sessions made from `.default` or `.ephemeral` configurations.
- Server-Sent Events with no code change: a `text/event-stream` response is listed while it's still open, with its events parsed as they arrive. See [Server-Sent Events](#server-sent-events).
- Background `URLSession` downloads and uploads with no code change, with their metrics but never their file or body.
- `URLSessionWebSocketTask` frames, pings, opens and closes with no code change.
- `NWConnection` through a drop-in wrapper, and any other socket engine through a one-line bridge.
- For each request: URL, method, query, headers, bodies, status and errors, plus a timing breakdown, sizes on the wire and after decoding, addresses, HTTP and TLS versions, and connection reuse.
- gzip and zlib bodies are decompressed for display.
- Protobuf bodies and binary socket frames are decoded to JSON when you add [rules](#protobuf-decoding) for them.

**Dashboard**

- **Floating trigger:** sits above your app, drags anywhere and snaps to the nearest side, and counts the requests since you last looked.
- **HTTP list:** newest first and live, with each method in its own colour (`GET` blue, `POST` green, `PUT` orange, `PATCH` purple, `DELETE` red) and an `SSE` tag on event streams, plus search by URL, method or status, and filters for 2xx, 4xx, 5xx and failed requests. The trash button clears every request and resets the session totals, after asking. Sockets are kept.
- **Log Inspector:** Response, Request and Metrics pages for each request. Tap a row to expand it, or long-press to copy it. An event stream's events are listed live at the end of the Response page.
- **Body Viewer:** pretty JSON or raw text, plus a collapsible tree for decoded protobuf, with copy and share buttons.
- **Sockets list:** every connection with its source (`WS`, `NW` or `EXT`), status, frame count and bytes sent and received.
- **Socket timeline:** each socket as a conversation with its frames, pings and state changes. Tap a frame to open it in the Body Viewer.
- **Proto Config:** each protobuf rule, what it maps to, where it came from and how often it has matched. Hidden when you have no rules.
- **System Info:** the network the device is on, how your requests are performing, session byte totals, downloads in progress, and the app and device. See [System Info](#system-info).
- **Copy and share:** copy any request as cURL from its page, or by swiping or long-pressing it in the list, and share a command or body as text or a file.
- **Export:** share one request as JSON, or the whole session as a HAR file. See [Export](#export).
- **Files:** browse, preview, rename, copy, move, delete, share and import the app's own files, in its data container, its bundle and any App Group container you name. See [Files](#files).

**Safety**

- Stays off in Ad Hoc, TestFlight and App Store builds unless you opt in. See [When Cerebro runs](#when-cerebro-runs).
- Redacts only what you select, before anything is stored: common credential headers, your own headers, body fields and query parameters. With no rules, `Authorization` and cookies are stored and shown as sent. See [Redaction](#redaction). Cerebro warns you before anything is shared. Files are never redacted: the Files tab shows them exactly as they are on disk.
- Keeps the live session in memory, capped by count and size, and sends nothing off the device. A redacted copy goes to the app's Caches folder, so the previous session survives a relaunch. See [Previous sessions](#previous-sessions).
- Lives in its own window, so it never touches your navigation stack or takes touches outside its own views.

## Configuration

Every setting is optional. `Cerebro.start()` uses the defaults, and calling it again while Cerebro runs does nothing, so call `stop()` first to change settings.

| Setting | Default | What it does |
|---|---|---|
| `allowsDistributionBuilds` | `false` | Runs capture in distribution-signed builds too. See [When Cerebro runs](#when-cerebro-runs) |
| `consoleLevel` | `.summary` | `.off`, `.summary` for one line per request, or `.full` for headers and bodies too |
| `requestLimit` | `500` | Requests kept. The oldest is dropped first |
| `bodyLimit` | `1_048_576` (1 MB) | Bytes stored for each request body, response body or socket frame. Longer ones are marked as truncated |
| `socketFrameLimit` | `1_000` | Frames and events kept for each socket. The oldest is dropped first |
| `redaction` | `RedactionRules()`, which redacts nothing | Headers, body fields and query parameters to redact. See [Redaction](#redaction) |
| `isShakeGestureEnabled` | `true` | Whether a shake shows or hides the floating button |
| `decoders` | `[]` | `BodyDecoder`s, tried in order, that turn a body Cerebro can't read into JSON. `registering(_:)` adds the [protobuf](#protobuf-decoding) one |
| `isPublicIPLookupEnabled` | `false` | Whether the System Info tab asks `api.ipify.org` for the device's public IP. See [System Info](#system-info) |
| `isPersistenceEnabled` | `true` | Whether each session is also kept on disk. See [Previous sessions](#previous-sessions) |
| `previousSessionLimit` | `1` | How many earlier sessions stay on disk |
| `isFileBrowserEnabled` | `true` | Whether the dashboard has a Files tab. See [Files](#files) |
| `appGroupIdentifiers` | `[]` | App Group containers the Files tab also shows, such as `"group.com.example.shared"` |

```swift
Cerebro.start(CerebroConfiguration(
    consoleLevel: .full,
    requestLimit: 100,
    bodyLimit: 256 * 1024
))
```

### Redaction

Cerebro redacts nothing until you select it. With no rules, `Authorization`, cookies and API keys appear in the dashboard, the console, Copy cURL and share exactly as sent. What you select is replaced with `[redacted]` before anything is stored (in a URL it reads `%5Bredacted%5D`), and names match in any letter case.

```swift
Cerebro.start(CerebroConfiguration(
    redaction: RedactionRules(
        sensitiveHeaders: [.authorization, .cookie, .setCookie],
        headers: ["X-Session-Id"],
        jsonKeys: ["password", "token"],
        queryParameters: ["api_key"]
    )
))
```

| Rule | Use it for |
|---|---|
| `sensitiveHeaders` | Common credential headers, picked from `SensitiveHeader`. Use `Set(SensitiveHeader.allCases)` for all of them |
| `headers` | Any header `SensitiveHeader` doesn't have |
| `jsonKeys` | Body fields: JSON keys at any depth in HTTP bodies and socket frames, and form-encoded fields in HTTP bodies |
| `queryParameters` | Secrets in URLs |

`SensitiveHeader` has `.authorization`, `.proxyAuthorization`, `.cookie`, `.setCookie`, `.apiKey`, `.xAPIKey`, `.xAuthToken`, `.xAccessToken`, `.xCSRFToken`, `.xXSRFToken`, `.xAmzSecurityToken` and `.xGoogAPIKey`.

Setting `jsonKeys` makes Cerebro parse bodies at capture, and a body it can't safely redact isn't stored:

- JSON that can't be parsed, and a JSON or form body that passed `bodyLimit`, is withheld.
- Other text that contains a key name anywhere is withheld whole, because it can't be redacted field by field. That includes a login page with `name="password"` and a form sent with no `Content-Type`. A short key such as `id` can hide a lot.
- Other text that names no key is stored as sent. So are binary bodies, including a multipart upload with a binary part.
- Protobuf that wasn't decoded is withheld. See [Protobuf decoding](#protobuf-decoding).

Redaction never touches the URL path or fragment, so keep secrets out of them.

## Traffic that needs code

iOS gives Cerebro no way to see these by itself, so each needs a small change. Skipping it only means that traffic isn't shown.

### NWConnection

Create a `MonitoredNWConnection` instead of an `NWConnection`. It has the same methods, and only forwards to the real connection while Cerebro is off.

```swift
import Cerebro
import Network

let connection = MonitoredNWConnection(host: "example.com", port: .https, using: .tls)
connection.stateUpdateHandler = { state in print(state) }
connection.start(queue: .main)
```

```swift
init(host: NWEndpoint.Host, port: NWEndpoint.Port, using parameters: NWParameters)
init(to endpoint: NWEndpoint, using parameters: NWParameters)
init(wrapping connection: NWConnection) // Keeps any state handler it already has.
```

Send and receive through the wrapper, because calls made directly on its `connection` property aren't recorded.

### Starscream, Socket.IO and other engines

Keep one `ExternalNetworkBridge.Connection` per socket, and make one call per frame or event:

```swift
let socket = ExternalNetworkBridge.Connection(name: "Prices", url: url)

ExternalNetworkBridge.log(.opened, on: socket)
ExternalNetworkBridge.log(.text(message), .sent, on: socket)
ExternalNetworkBridge.log(.binary(data), .received, on: socket)
ExternalNetworkBridge.log(.closed(code: 1000, reason: "done"), on: socket)
```

```swift
// On ExternalNetworkBridge:
struct Connection { init(name: String, url: URL? = nil) }
static func log(_ payload: SocketPayload, _ direction: SocketDirection, on connection: Connection)
static func log(_ event: SocketEvent, on connection: Connection)
```

| Type | Cases |
|---|---|
| `SocketPayload` | `.text(String)`, `.binary(Data)` |
| `SocketDirection` | `.sent`, `.received` |
| `SocketEvent` | `.opened`, `.closed(code: Int?, reason: String?)`, `.ping`, `.pong`, `.stateChanged(String)`, `.failed(String)` |

## Protobuf decoding

Binary protobuf in HTTP bodies and binary socket frames can show as readable JSON. You say which traffic uses which message, and Cerebro uses the `.pb.swift` types your app already has. It never needs `.proto` files.

### 1. Add the decoder

| Install option | What to add |
|---|---|
| Swift Package Manager | The **CerebroProto** product, on your app target |
| CocoaPods | `:subspecs => ['Core', 'UI', 'Proto']` on your `pod 'Cerebro'` line |
| XCFramework | [`CerebroProto.xcframework.zip`](https://github.com/0xSiddhant/Cerebro/releases/latest/download/CerebroProto.xcframework.zip) and [`SwiftProtobuf.xcframework.zip`](https://github.com/0xSiddhant/Cerebro/releases/latest/download/SwiftProtobuf.xcframework.zip), set to **Embed & Sign** |

An app that doesn't add it never links SwiftProtobuf.

### 2. Write your rules

Rules can live in code, in a `traffic_map.json` file, or both.

```swift
import Cerebro
import CerebroProto // Leave this out with CocoaPods, where `ProtoRule` comes from `import Cerebro`.

let rule = ProtoRule(
    name: "Stock quote",
    match: .init(host: "api.example.com", pathPrefix: "/v1/quotes"),
    methods: ["GET"],
    direction: .response,
    messageType: Market_V1_QuoteResponse.self
)

Cerebro.start(CerebroConfiguration().registering([rule] + ProtoRule.generated))
```

Leave out `ProtoRule.generated` if you don't use a file. Code rules are checked first, then file rules in file order, and the first match wins.

| Part | Meaning |
|---|---|
| `match` | Any of `host`, `path`, `pathPrefix` and `regex`, which is searched for in the URL's path. Every part you set has to match |
| `methods` | The HTTP methods the rule applies to. Empty means any |
| `direction` | `.request`, `.response`, `.socketOutgoing` or `.socketIncoming`. Socket rules only apply to binary frames |
| `stripPrefixBytes` | Bytes to drop before decoding, such as `5` for gRPC-web's header |

`traffic_map.json` uses full proto names, so one file can be shared with Android and your backend:

```json
{
  "version": 1,
  "rules": [
    {
      "name": "Place order",
      "match": { "host": "api.example.com", "path": "/v1/orders" },
      "methods": ["POST"],
      "request": "orders.v1.PlaceOrderRequest",
      "response": "orders.v1.PlaceOrderResponse"
    },
    {
      "name": "Live ticks",
      "match": { "host": "stream.example.com", "path": "/v1/ticks" },
      "socket": { "outgoing": "market.v1.SubscribeRequest", "incoming": "market.v1.Tick" }
    },
    {
      "name": "gRPC-web search",
      "match": { "pathPrefix": "/grpc/search.v1.SearchService/" },
      "framing": { "stripPrefixBytes": 5 },
      "response": "search.v1.SearchResponse"
    }
  ]
}
```

### 3. Generate `ProtoRule.generated`

You only need this step for `traffic_map.json`. A name that matches no type in your `.pb.swift` files fails the build and says which one, and so does a key the format doesn't have, such as `pathprefix`.

**Swift Package Manager.** Put `traffic_map.json` next to your `.xcodeproj`, or inside the target. In the target's **Build Phases**, add `CerebroProtoPlugin` under **Run Build Tool Plug-ins**. Xcode asks once to trust it, and command-line builds on CI need `-skipPackagePluginValidation`. A package target uses `plugins: [.plugin(name: "CerebroProtoPlugin", package: "Cerebro")]`.

**CocoaPods and XCFramework.** These have no build plugins, so a **Run Script** phase runs the same generator. Place the phase above **Compile Sources**:

```sh
"${PODS_ROOT}/Cerebro/bin/cerebro-proto-gen" \
    --map "${SRCROOT}/traffic_map.json" \
    --sources "${SRCROOT}/MyApp" \
    --output "${SRCROOT}/MyApp/CerebroProtoRules.generated.swift"
```

- With an XCFramework, download [`cerebro-proto-gen.zip`](https://github.com/0xSiddhant/Cerebro/releases/latest/download/cerebro-proto-gen.zip) and use its path instead. macOS blocks a downloaded binary until you run `xattr -d com.apple.quarantine cerebro-proto-gen`.
- Build once, then add the generated file to your target.
- If **User Script Sandboxing** is on, turn it off for this target, or list the map, sources and output as the phase's input and output files.

### What you'll see

| In the Log Inspector | Meaning | Shown as |
|---|---|---|
| `decoded` | A rule matched and the body decoded | A collapsible tree, with Pretty and Raw alongside. Raw is the original bytes in hex, or the redacted JSON with `jsonKeys` set |
| `proto, no rule` | The content type says protobuf, but no rule matched | Hex |
| `proto, too large to decode` | The body, or the JSON it decodes to, is over `bodyLimit` | Hex, marked as truncated if it was cut off |
| `proto, couldn't be decoded` | A rule matched, but the bytes aren't that message | Hex |

The content types recognized without a rule are `application/x-protobuf`, `application/protobuf` and `application/grpc`, except gRPC's `+json` and `-text` forms. A rule never applies to a body whose content type says it's text, so a JSON error from a protobuf endpoint still shows as JSON. Binary socket frames that no rule matches also show as hex. With `consoleLevel: .full`, decoded bodies print as JSON.

The **Proto Config** tab lists each rule, what it maps to, whether it came from code or `traffic_map.json`, and how often it has matched. It's hidden when you have no rules.

### Redacting protobuf

Decoded bodies are redacted like any other JSON, and the keys are the field names in your `.proto` file, such as `card_number` rather than `cardNumber`. With `jsonKeys` set, a decoded body's original bytes aren't kept, because a field your `.pb.swift` files don't know is in those bytes but not in the JSON that was redacted. Protobuf that wasn't decoded is withheld, because its values can't be matched to keys, and so is gRPC-web's base64 text form.

## Server-Sent Events

Cerebro shows a Server-Sent Events (SSE) stream while it's open, with no code change. Other requests appear in the HTTP list when they finish, which a stream may never do.

**What counts as a stream.** A response with status 200 and the media type `text/event-stream`, in any letter case and with or without parameters such as `charset`, made through the same `URLSession` path as other captured requests. That covers `URLSession.bytes(for:)`, data tasks, delegate-based clients and third-party libraries built on `URLSession`, however the request was started, including a `POST`. Any other response is captured as before, with its body.

**What you see.**

- The request joins the HTTP list as soon as its response arrives. Its row carries an `SSE` tag beside the method, teal with a dot while the stream is live and grey once it closes, is cancelled or fails, and it counts its events. It stays one row throughout.
- On the request's page, the summary shows whether the stream is live and how many events it has had, and the Response page lists the events last, after the headers. Each event shows its type, its ID if the stream set one, when it arrived and the start of its data. Tap one to open its data in the Body Viewer. The page updates while it's open.
- A stream has no response body. Its events are what's kept.

**How events are read.** Cerebro follows the standard event stream format. Lines can end in LF, CR or CRLF, a leading byte order mark is skipped, and it doesn't matter how the bytes are split as they arrive. An event is recorded at each blank line if it has a `data` field, and several `data` lines join with line breaks. The type is `message` unless an `event` field names another, and an ID stays in effect until the stream sets a new one. Comment lines, which many servers send to keep a stream alive, and `retry` fields aren't events. Cerebro never reconnects a stream or replays one: it watches your app's connection.

**Limits.**

- Each stream keeps its newest 1,000 events, and at most `bodyLimit` bytes of them (1 MB by default). Past either, the oldest go. The count keeps counting every event, and the Events heading shows `newest 1,000 of 5,230`.
- Your app always gets every byte first and unchanged. If events arrive faster than Cerebro can read them, by more than `bodyLimit`, or one event is larger than `bodyLimit`, Cerebro stops reading that stream and marks its events incomplete. The stream itself still works and still shows when it ends. A large chunk on its own is fine: only a backlog or a single oversized event stops the reading.
- The request cap still applies. If a long-lived stream becomes the oldest row and the list is full, it's dropped like any other request and doesn't come back.
- Clearing the HTTP list removes a live stream with everything else. If it's still running, it comes back at its next event, with only the events that arrived after the clear.
- If a stream's page is open when the stream leaves the list, the page keeps what it had and shows the stream as `Not tracked`.
- `Cerebro.stop()` closes every stream that's still open with the events it has, since its real end can no longer be recorded.
- While the dashboard is closed, an open stream costs nothing on the main thread.

**Redaction.** Each event goes through [redaction](#redaction) before it's stored, so the dashboard, console, exports and saved sessions never hold the raw value.

- With `jsonKeys` set, JSON data has those keys redacted. Data that looks like JSON but doesn't parse is withheld, and so is plain text that names a key. The `[DONE]` marker many streaming APIs send is one of these: it starts like a JSON array, so with `jsonKeys` set it shows as withheld.
- An event's type or ID that contains a configured key name becomes `[redacted]`.

**Console, export and saved sessions.** A stream is printed once, when it ends, and `.full` adds its events. The JSON export has an `eventStream` object and a HAR entry has `_eventStream`, both with the stream's state, counts and events. A stream is saved to the [previous session](#previous-sessions) when it ends, so one still open when the app exits isn't there after a relaunch.

**Quiet streams and timeouts.** Cerebro runs each request through its own session, so a timeout set on your `URLSessionConfiguration` doesn't apply, as described in [What changes while Cerebro captures](#what-changes-while-cerebro-captures). The default of 60 seconds without data applies in its place, even if your configuration allows longer. If your stream can stay quiet for longer than that, set `timeoutInterval` on the `URLRequest`, which does carry over, or have the server send a comment line as a keep-alive.

**Try it.** The [Example](../Example) app has two samples, a short stream at launch and a one-minute stream you start with a tap, both served by a small server inside the app. Their events show a redacted key, a multi-line event, a comment and a withheld `[DONE]`.

**Not captured.** Streams from a `WKWebView`, from a networking stack that doesn't use `URLSession`, and from background sessions, which report only their metrics.

## Background transfers

Uploads and downloads through a background `URLSession` are captured with no code change. Each one appears in the HTTP list with its URL, status, headers, timing, connection details and sizes. Your session delegate still gets every callback, and `session.delegate` still returns it.

- The file or body is never read or stored. It shows as not stored, with its size.
- A redirected transfer is one row describing its last hop, and its sizes count every hop.
- A transfer appears only once it finishes. One that iOS keeps retrying, such as a refused connection, stays unseen until it ends, which can take days.
- `Cerebro.start()` has to run before the session is created. A session created in a property of your app delegate is too early.
- If iOS relaunches your app to finish a transfer, the transfer appears in that launch's log, once your app recreates the session with the same identifier.
- A transfer is saved to the session file when it finishes, like any other request, so it's still in that launch's [saved session](#previous-sessions) if iOS later ends the app.

## System Info

The System Info tab shows the network a request ran on, what the session has moved, and the app and device, using only what iOS exposes publicly. Nothing on it runs until you open the tab. A card at the top says whether the device is online and over what, and flags a VPN, a proxy or Low Data Mode while one applies. Tap any row to copy its value.

| Page | Section | What it shows |
|---|---|---|
| Network | Connection | The type (Wi-Fi, cellular, wired or other), the cellular generation, Low Data Mode, whether the connection is metered, and whether a VPN or proxy is active |
| Network | IP addresses | The device's Wi-Fi (`en0`) and cellular (`pdp_ip0`) IPv4 and IPv6 addresses, and the public IP |
| Traffic | Downloads in progress | Each foreground download still running, with its bytes so far and its progress if the server announced a size |
| Traffic | Performance | An overall rating, server response time, connection setup time and download speed, averaged over the last 20 requests |
| Traffic | This session | Requests, bytes sent and bytes received since `Cerebro.start()`, then by host and by connection |
| Device | App | Name, version and build, bundle ID and minimum iOS version |
| Device | Device | Model, hardware identifier such as `iPhone17,3`, iOS version, memory, processor cores, Low Power Mode, locale and time zone |

- **Public IP:** off by default, and the row says `Off`. Set `isPublicIPLookupEnabled` to turn it on. Cerebro then sends one request to `https://api.ipify.org` when you open the tab, and again if the network changes while the dashboard is open. Nothing is sent while it's closed. It's the only data Cerebro sends off the device, and that request never appears in the HTTP list or the console.
- **Performance** stands in for signal strength, which iOS doesn't expose. It describes your app's own requests, not the network alone, so a slow server reads as slow.
  - The rating comes from the average response time: Good under 300 ms, Fair under 1 second, and Slow above that.
  - Response time is how long a server took to start answering.
  - Connection setup only counts requests that opened a new connection.
  - Download speed only counts responses of 64 KB or more, because a small one measures the server's delay, not the network's speed. The row is hidden until there is one.
- **Totals** are a running sum of captured requests, so they stay correct after old requests leave the list. Clearing the HTTP list starts them again. They don't include sockets or other apps' traffic. Only the first 50 hosts get their own line.
- **Downloads** made with a download task, including image loaders built on one, keep their size, duration, throughput and MIME type but never their body. A [background transfer](#background-transfers) has no progress, because it only appears once it finishes.
- While the tab shows the device as offline, it checks the network again every 2 seconds, because iOS can miss the connection coming back, most often on a simulator.
- A VPN or proxy is detected from the system's proxy settings, so a VPN that doesn't register there isn't seen. On a simulator, these and the memory and processor counts reflect the Mac.

Signal strength, carrier name and Wi-Fi name aren't shown, because iOS has no public API for the first, deprecated the second, and needs an entitlement and location permission for the third. The device's own name, battery level and free storage aren't shown either: iOS returns a generic name, and the other two would need Cerebro to change app settings or declare a privacy reason on your app's behalf.

## Previous sessions

Cerebro keeps each session on disk as well as in memory, so you can still read what happened before a crash or a relaunch. Tap the clock button at the top of the HTTP or Sockets list and pick a session. It opens in the same list, read-only: you can open requests and export them, but not clear them.

- **What's saved:** every finished HTTP request and every socket frame and event, exactly as the dashboard shows them. Redaction ran first, so a redacted value never reaches the disk.
- **Where:** one JSON Lines file per session in `Library/Caches/Cerebro/Sessions`, inside your app's own container. Nothing leaves the device, and iOS may delete Caches when the device is short of space.
- **When:** each request or frame is written as it finishes, on a background queue, so a crash loses at most what was still in flight.
- **How much:** a session's file keeps the newest `requestLimit` requests and at most 50 MB. Past either, the oldest lines are dropped. One earlier session is kept by default, and older ones are removed at each launch. Raise `previousSessionLimit` to keep more.
- **Clearing** the HTTP list also clears those requests from the saved session.
- **Turning it off:** `isPersistenceEnabled: false` writes nothing, and removes what earlier launches saved.

A request that hadn't finished when the app ended isn't in the file, and neither is a download still in progress or an event stream that was still open.

## Export

Every export goes through the share sheet, which warns first, because captured data can hold anything you didn't [redact](#redaction). Redacted values are never in an export, since they were removed before storage.

| Export | Where | Format |
|---|---|---|
| cURL | A request's page, or a swipe or long-press in the HTTP list | A command to paste into a terminal |
| One request as JSON | The share button on a request's page | One document with the URL, headers, bodies, status, timing, connection and sizes |
| The session as HAR | The share button at the top of the HTTP list | HAR 1.2, which browser developer tools, Charles and Proxyman can open |

- A HAR export holds every request in the list, not only the ones your search or filter shows.
- A body that isn't text is written as Base64. One that was cut off, withheld or not stored has a comment saying so.
- A [Server-Sent Events](#server-sent-events) stream is exported with the events it holds at that moment, and its `state` says whether it was still open.
- A whole session can be large: up to twice `bodyLimit` for each of `requestLimit` requests. Lower either if exports are too big to share.

## Files

The Files tab shows your app's sandbox as folders and files, so you can see what your app wrote to disk, such as a stale cache, a bad preferences file or a database that should have been removed, without downloading the container from Xcode. It needs no code.

It opens on a list of locations, each with its size:

| Location | What it is | Changes |
|---|---|---|
| Data Container | Your app's home folder, with `Documents`, `Library`, `tmp` and `SystemData` | Allowed |
| App Bundle | The installed app | Never. It's signed on a device, and Cerebro refuses changes on a simulator too, so both behave the same |
| Each App Group you name | A container your app shares with a widget or an extension | Allowed |

Open a location to see its folders, one level per screen. Tap the title to jump back to any folder above. Each row shows the item's size and when it changed, and a folder's size and item count appear once its row is on screen. Hidden files are listed like any other. A symbolic link is listed as a link with its target.

- **Sort** by name, date modified or size from the **⋯** menu. Folders always come first.
- **Search** by name in **This Folder**, or in **Subfolders**, which lists where each match is.
- **Live:** a file your app adds, removes or renames shows up while its folder is open. A file that only grew keeps its old size until you pull down to refresh.

### Previews

Tap a file to open it in the viewer that suits it:

| File | Opens in |
|---|---|
| Property list, binary or XML, by its extension or its first bytes | The Body Viewer, as JSON with a tree view. This makes `Library/Preferences`, where `UserDefaults` lives, readable. A date is shown in ISO 8601 and data as Base64 |
| JSON | The Body Viewer, pretty-printed |
| Images, PDF, audio, video, HTML, RTF, CSV, office and iWork documents, plain text | Quick Look, with zoom, paging and text search |
| Anything else, such as SQLite or a file with no extension | The Body Viewer, as text if it's UTF-8 and as hex if not |

The Body Viewer reads at most `bodyLimit` bytes, 1 MB by default, and says when a file was cut off. A property list over `bodyLimit` isn't converted and opens as hex. If a guess is wrong, long-press the file and choose **Open in Quick Look** or **Open as Text or Hex**. The first Quick Look preview can take a few seconds to appear. Quick Look's editing and markup are off.

### Actions

Long-press an item for its menu, or swipe it: left for Delete and Share, right for Info. Choose **Select** from the **⋯** menu to act on several items at once.

| Action | On | What it does |
|---|---|---|
| Open in Quick Look, Open as Text or Hex | A file | Overrides the viewer Cerebro picked |
| Info | One item | Name, type, location, path, size, created and modified dates, whether it's writable, permissions, data protection class, whether it's backed up, a link's target, and a folder's contents |
| Copy Path | One item | The full path, or the path inside its location, such as `Library/Preferences/com.example.plist` |
| Share | One item or a selection | Through the share sheet, after a warning. A folder is zipped first |
| Rename | One item | Refused if the name is taken, empty, `.` or `..`, or holds a `/` |
| Duplicate | One item | Makes `name 2.ext` beside it |
| Copy To, Move To | One item or a selection | To a folder you pick in the same location |
| Delete | One item or a selection | Asks first, and says how many items its folders hold |
| Delete Contents | A folder | Empties it and keeps the folder, for `Caches` and `tmp`. Asks first |
| New Folder, Import File | The open folder, from the **⋯** menu | Import copies in a file you pick with the system's document picker, to seed test data |

- **Nothing is overwritten.** A copy, a move or an import into a folder that already has that name gets `name 2.ext`, then `name 3.ext`. A rename or a new folder with a taken name is refused.
- **Nothing can be undone,** which is why both deletes ask first.
- **Only what applies is offered.** The app bundle's items, and any item your app can't write, offer only the previews, Info, Copy Path and Share.
- **A failure changes nothing else.** It shows the system's reason.
- **Nothing outside a location can be reached.** Every path is checked after following symbolic links, so a link or a name such as `..` that leads outside is refused. A device's sandbox already stops that, but a simulator doesn't, and this keeps Cerebro away from your Mac's files. Deleting or renaming a link changes the link, never its target.

Deleting `Library/Caches/Cerebro` only removes the [saved sessions](#previous-sessions).

### Your app doesn't see the change

Cerebro changes files, not your app's memory. If your app has a database open, or already read `UserDefaults`, it keeps its own copy until it reads again. **Relaunch your app** after changing a file it holds open.

### Privacy

Files aren't redacted. Your [redaction rules](#redaction) name headers, body keys and query parameters in traffic, and don't apply to files, which the tab shows exactly as they are on disk. Browsing copies, stores and sends nothing. A file leaves the device only when you share it, and Cerebro's Share warns first.

Quick Look's own share button is the exception: it shares the file with no warning, because iOS has no public way to remove it.

### Settings

- `isFileBrowserEnabled: false` removes the tab, for example in builds you give testers with `allowsDistributionBuilds`, where you want traffic inspection without the power to delete your app's data.
- `appGroupIdentifiers` adds each App Group container. iOS can't tell Cerebro which groups your app has, so name them:

```swift
Cerebro.start(CerebroConfiguration(appGroupIdentifiers: ["group.com.example.shared"]))
```

A group your app isn't entitled to is left out, and the console says which.

### Limits

- A folder's size and item count stop at 20,000 items, and then say "more than".
- A search through subfolders stops at 50,000 items looked at or 500 matches, and says so.
- Listing, sizes, search and every action run off the main thread, and leaving a screen stops its sizes.
- Not shown: the Keychain, which isn't files, iCloud containers, and thumbnails. A file's contents can't be edited.

## When Cerebro runs

`Cerebro.start()` decides from how the app is signed. Every install option uses the same check.

| Build | Capture |
|---|---|
| Simulator | On |
| Development-signed (`get-task-allow` in the provisioning profile) | On |
| Ad Hoc, TestFlight, App Store | Off, unless `allowsDistributionBuilds` is `true` |

The check reads the signing, not the build configuration, so a Release build signed for development still captures. While Cerebro is off, nothing is hooked, no dashboard appears, `MonitoredNWConnection` only forwards and `ExternalNetworkBridge` does nothing.

To capture in a QA or TestFlight build, opt in:

```swift
Cerebro.start(CerebroConfiguration(allowsDistributionBuilds: true))
```

This turns capture on in every distribution build, App Store included, so set it only in builds that won't ship there.

### Leaving Cerebro out of Release builds

The check above already keeps Cerebro off, so this is optional.

With CocoaPods, add `:configurations => ['Debug']` to the `pod` line, and Release builds won't contain Cerebro at all. The module doesn't exist there, so guard your code with `canImport`:

```swift
#if canImport(Cerebro)
import Cerebro
#endif

// In your start-up code:
#if canImport(Cerebro)
Cerebro.start()
#endif
```

SPM and XCFrameworks link Cerebro in every configuration, so its code stays in the Release binary. Wrapping the import and the call in `#if DEBUG` only stops your code from calling it.

## What changes while Cerebro captures

Cerebro sends each request through its own session, which has these side effects in builds where it runs. Background sessions don't go through it, so they aren't affected:

- Settings on your `URLSessionConfiguration` other than headers don't apply, such as timeouts, cellular access and cookie handling. For a long-lived stream this matters most: see [Server-Sent Events](#server-sent-events).
- The `urlSession(_:task:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)` upload progress callback doesn't fire.
- HTTP Basic, Digest and NTLM logins answered by a session delegate aren't answered, so your app receives the 401.
- A redirect your session delegate refuses arrives about 500 ms later. Followed redirects aren't delayed.

Certificate pinning and client certificates keep working, because those challenges still reach your delegate.

Cerebro keeps both the request and response body of up to 500 requests, so it can hold about 1 GB at worst. Lower `requestLimit` or `bodyLimit` if your app moves many large bodies. Sockets are capped separately: 100 connections and 100 times `bodyLimit` of payload (100 MB by default), and the socket idle longest goes first.

## What Cerebro can't capture

- WKWebView traffic
- AVPlayer streams
- gRPC over SwiftNIO
- Sockets not routed through `MonitoredNWConnection` or `ExternalNetworkBridge`

## Troubleshooting

| What you see | Likely cause | Fix |
|---|---|---|
| No floating button | `Cerebro.start()` didn't run, or the build is signed for distribution | Check the call runs. For Ad Hoc or TestFlight, set `allowsDistributionBuilds` |
| The floating button disappeared | A shake hid it | Shake again |
| An event's data says withheld | `jsonKeys` is set and the data couldn't be redacted safely, such as `[DONE]` | Expected. See [Server-Sent Events](#server-sent-events) |
| A stream ends after a minute of silence only while Cerebro runs | Its timeout is set on the `URLSessionConfiguration`, which Cerebro's session doesn't see | Set `timeoutInterval` on the `URLRequest`, or send keep-alive comments |
| Some requests are missing | Their session or configuration was made before `Cerebro.start()` | Call it earlier, and check stored properties on your `AppDelegate` or `App` |
| One session's requests are all missing | Your code assigned `protocolClasses`, which removes Cerebro's | Add to the array instead: `configuration.protocolClasses = (configuration.protocolClasses ?? []) + [MyProtocol.self]` |
| A body says `proto, no rule` | Its content type says protobuf, but no rule matched | Add a [rule](#protobuf-decoding), and check its host, path and direction |
| Build error: `no type in the .pb.swift files matches` | A name in `traffic_map.json` isn't in the files the generator read | Use the full proto name with its package, and check the `.pb.swift` file is in the target or under `--sources` |
| No Proto Config tab | No rules were registered | Pass them to `registering(_:)` |
| A socket is missing | It's a raw `NWConnection` or a third-party engine | See [Traffic that needs code](#traffic-that-needs-code) |
| No Files tab | `isFileBrowserEnabled` is `false` | Remove the setting, or set it to `true` |
| An App Group isn't in the Files tab | It isn't named in `appGroupIdentifiers`, or the app isn't entitled to it. The console says which | Name it, and check the App Groups capability of the app's target |
| A file you changed in the Files tab didn't change in your app | Your app read it before and kept its own copy | Relaunch your app. See [Files](#files) |
| `Authorization`, cookies or tokens are visible | Cerebro redacts nothing until you select it | Select them in `RedactionRules`. See [Redaction](#redaction) |
| A body says it's withheld | `jsonKeys` are set and the body couldn't be redacted: it couldn't be parsed, it passed `bodyLimit`, or it's other text containing a key name | Expected, because a body that can't be redacted isn't stored. Raise `bodyLimit` if it was cut off, or use a longer key if a short one matches too much |
| `No such module 'Cerebro'` | The product isn't linked to this target, or you opened the `.xcodeproj` of a CocoaPods app | Add the `Cerebro` product to the target, or open the `.xcworkspace` |
| Crash at launch: `Library not loaded: @rpath/Cerebro.framework/Cerebro` | The XCFramework isn't embedded | Set it to **Embed & Sign** |
| Timeouts or cookies behave differently | Cerebro sends requests through its own session | See [What changes while Cerebro captures](#what-changes-while-cerebro-captures) |
