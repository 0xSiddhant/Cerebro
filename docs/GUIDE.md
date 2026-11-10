# Cerebro guide

Installing and starting Cerebro is in the [README](../README.md). This guide covers everything after that.

- [Features](#features)
- [Configuration](#configuration)
  - [Redaction](#redaction)
- [Traffic that needs code](#traffic-that-needs-code)
- [Protobuf decoding](#protobuf-decoding)
- [Background transfers](#background-transfers)
- [When Cerebro runs](#when-cerebro-runs)
- [What changes while Cerebro captures](#what-changes-while-cerebro-captures)
- [What Cerebro can't capture](#what-cerebro-cant-capture)
- [Troubleshooting](#troubleshooting)

## Features

**Capture**

- `URLSession` traffic with no code change, including `URLSession.shared` and sessions made from `.default` or `.ephemeral` configurations.
- Background `URLSession` downloads and uploads with no code change, with their metrics but never their file or body.
- `URLSessionWebSocketTask` frames, pings, opens and closes with no code change.
- `NWConnection` through a drop-in wrapper, and any other socket engine through a one-line bridge.
- For each request: URL, method, query, headers, bodies, status and errors, plus a timing breakdown, sizes on the wire and after decoding, addresses, HTTP and TLS versions, and connection reuse.
- gzip and zlib bodies are decompressed for display.
- Protobuf bodies and binary socket frames are decoded to JSON when you add [rules](#protobuf-decoding) for them.

**Dashboard**

- **Floating trigger:** sits above your app, drags anywhere and snaps to the nearest side, and counts the requests since you last looked.
- **HTTP list:** newest first and live, with search by URL, method or status, and filters for 2xx, 4xx, 5xx and failed requests.
- **Log Inspector:** Response, Request and Metrics pages for each request. Tap a row to expand it, or long-press to copy it.
- **Body Viewer:** pretty JSON or raw text, plus a collapsible tree for decoded protobuf, with copy and share buttons.
- **Sockets list:** every connection with its source (`WS`, `NW` or `EXT`), status, frame count and bytes sent and received.
- **Socket timeline:** each socket as a conversation with its frames, pings and state changes. Tap a frame to open it in the Body Viewer.
- **Proto Config:** each protobuf rule, what it maps to, where it came from and how often it has matched. Hidden when you have no rules.
- **Copy and share:** copy any request as cURL from its page, or by swiping or long-pressing it in the list, and share a command or body as text or a file.

**Safety**

- Stays off in Ad Hoc, TestFlight and App Store builds unless you opt in. See [When Cerebro runs](#when-cerebro-runs).
- Redacts only what you select, before anything is stored: common credential headers, your own headers, body fields and query parameters. With no rules, `Authorization` and cookies are stored and shown as sent. See [Redaction](#redaction). Cerebro warns you before anything is shared.
- Keeps everything in memory, capped by count and size, and sends nothing off the device.
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

## Background transfers

Uploads and downloads through a background `URLSession` are captured with no code change. Each one appears in the HTTP list with its URL, status, headers, timing, connection details and sizes. Your session delegate still gets every callback, and `session.delegate` still returns it.

- The file or body is never read or stored. It shows as not stored, with its size.
- A redirected transfer is one row describing its last hop, and its sizes count every hop.
- A transfer appears only once it finishes. One that iOS keeps retrying, such as a refused connection, stays unseen until it ends, which can take days.
- `Cerebro.start()` has to run before the session is created. A session created in a property of your app delegate is too early.
- If iOS relaunches your app to finish a transfer, the transfer appears in that launch's log, once your app recreates the session with the same identifier.
- Rows are in memory, so they're lost if iOS later ends the app.

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

- Settings on your `URLSessionConfiguration` other than headers don't apply, such as timeouts, cellular access and cookie handling.
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
| Some requests are missing | Their session or configuration was made before `Cerebro.start()` | Call it earlier, and check stored properties on your `AppDelegate` or `App` |
| One session's requests are all missing | Your code assigned `protocolClasses`, which removes Cerebro's | Add to the array instead: `configuration.protocolClasses = (configuration.protocolClasses ?? []) + [MyProtocol.self]` |
| A body says `proto, no rule` | Its content type says protobuf, but no rule matched | Add a [rule](#protobuf-decoding), and check its host, path and direction |
| Build error: `no type in the .pb.swift files matches` | A name in `traffic_map.json` isn't in the files the generator read | Use the full proto name with its package, and check the `.pb.swift` file is in the target or under `--sources` |
| No Proto Config tab | No rules were registered | Pass them to `registering(_:)` |
| A socket is missing | It's a raw `NWConnection` or a third-party engine | See [Traffic that needs code](#traffic-that-needs-code) |
| `Authorization`, cookies or tokens are visible | Cerebro redacts nothing until you select it | Select them in `RedactionRules`. See [Redaction](#redaction) |
| A body says it's withheld | `jsonKeys` are set and the body couldn't be redacted: it couldn't be parsed, it passed `bodyLimit`, or it's other text containing a key name | Expected, because a body that can't be redacted isn't stored. Raise `bodyLimit` if it was cut off, or use a longer key if a short one matches too much |
| `No such module 'Cerebro'` | The product isn't linked to this target, or you opened the `.xcodeproj` of a CocoaPods app | Add the `Cerebro` product to the target, or open the `.xcworkspace` |
| Crash at launch: `Library not loaded: @rpath/Cerebro.framework/Cerebro` | The XCFramework isn't embedded | Set it to **Embed & Sign** |
| Timeouts or cookies behave differently | Cerebro sends requests through its own session | See [What changes while Cerebro captures](#what-changes-while-cerebro-captures) |
