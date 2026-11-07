# PLAN-03 — Protobuf decoding and the Proto Config tab

## Goal

Binary protobuf in HTTP bodies and socket frames becomes readable JSON. Apps define rules in code or in a `traffic_map.json` file, and a tab shows which rules are active and matching.

## Gate

PLAN-02 merged. Single PR on `plan/3-proto`.

## Scope

**In:** `CerebroProto` rules, content-type detection, prefix stripping, decoding of HTTP bodies and binary frames; `CerebroProtoGenerator`, `CerebroProtoPlugin` and the `cerebro-proto-gen` binary; the Example app wired through both rule paths; the collapsible JSON tree; the Proto Config tab.

**Out:** the raw wire-format view, which is not planned yet. `.proto` files are never needed.

## Decisions & reasoning

### Two rule sources, one rule type

Rules are written in code, or generated as `ProtoRule.generated` from `traffic_map.json`. The app passes both to `Cerebro.start`. Code rules work in every channel and are type-checked, and the JSON uses proto names, so one file can be shared with Android and the backend. Code rules are checked first, then file rules in file order, and the first match wins.

### The generator resolves names at build time

`traffic_map.json` uses full proto message names. The generator resolves each one to the app's generated Swift type by scanning its `.pb.swift` files, and fails the build if a name matches no type. For example, `market.v1.QuoteResponse` becomes `Market_V1_QuoteResponse`.

### One generator, two ways to run it

SPM users run it through the `CerebroProtoPlugin` build-tool plugin. CocoaPods has no build plugins, so Pod and XCFramework users run the same generator, shipped as the `cerebro-proto-gen` binary, from a Run Script build phase. Xcode asks once to trust the plugin, and CI builds pass `-skipPackagePluginValidation`.

### SwiftProtobuf stays optional

Decoding lives in `CerebroProto`, so apps that don't use protobuf never link it. The dependency keeps a broad version range so it doesn't clash with the host app's version. Message types come from the app's own generated `.pb.swift` code.

### The dashboard can't import `CerebroProto`

`Cerebro` depends only on `CerebroCore`, so the Proto Config tab reads rules through the decoder plugin interface in the core, never through `CerebroProto` types.

### The Proto Config tab hides when there is nothing to show

When no proto decoder is registered, the tab is hidden, since it could only ever be empty.

### Only apps that decode protobuf write code for it

They pass their rules to `Cerebro.start`, as the spec says. Finding generated rules at runtime would save that one argument but add a lookup by name in all three install options, so it fails the same trade-off as auto-start. A Pod is one module, so those apps use `import Cerebro` rather than `import CerebroProto`.

## Public API

| API | Purpose | Notes |
|---|---|---|
| `ProtoRule` | Matcher + direction + message type | Matcher: host, path, path prefix or regex, with an optional HTTP method. Direction: request, response or socket frame |
| `ProtoRule.generated` | Rules generated from `traffic_map.json` | Passed to `Cerebro.start` with code rules |
| `traffic_map.json` | Rule file | Format below |
| `CerebroProtoPlugin` | SPM build-tool plugin | Runs the generator on the app's target |
| `cerebro-proto-gen` | Generator binary | For Run Script phases |

### `traffic_map.json` format

```json
{
  "version": 1,
  "rules": [
    {
      "name": "Stock quote",
      "match": { "host": "api.example.com", "pathPrefix": "/v1/quotes" },
      "methods": ["GET"],
      "response": "market.v1.QuoteResponse"
    },
    {
      "name": "Place order",
      "match": { "host": "api.example.com", "path": "/v1/orders" },
      "methods": ["POST"],
      "request": "orders.v1.PlaceOrderRequest",
      "response": "orders.v1.PlaceOrderResponse"
    },
    {
      "name": "Holdings",
      "match": { "regex": "^/v1/portfolio/[0-9]+/holdings$" },
      "response": "portfolio.v1.HoldingsResponse"
    },
    {
      "name": "Live ticks",
      "match": { "host": "stream.example.com", "path": "/v1/ticks" },
      "socket": {
        "outgoing": "market.v1.SubscribeRequest",
        "incoming": "market.v1.Tick"
      }
    },
    {
      "name": "gRPC-web search",
      "match": { "pathPrefix": "/grpc/search.v1.SearchService/" },
      "framing": { "stripPrefixBytes": 5 },
      "request": "search.v1.SearchRequest",
      "response": "search.v1.SearchResponse"
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `version` | Format version, so the plugin can change the schema later |
| `name` | Label shown on the Proto Config tab |
| `match` | `host`, `path`, `pathPrefix` or `regex` |
| `methods` | Optional filter on the HTTP method |
| `request` / `response` | Full proto message name |
| `socket` | Message type for each direction of WebSocket frames |
| `framing.stripPrefixBytes` | Bytes to drop before decoding, e.g. 5 for gRPC-web |

## Task checklist

**Rules and decoding (`Sources/CerebroProto/`)**
- [ ] Replace the `ProtoRule` placeholder with the matcher, direction, message type and optional framing
- [ ] Replace the `registering` placeholder with rule registration at start
- [ ] Decoder plugin for HTTP bodies and binary frames, producing pretty-printed JSON
- [ ] Prefix strip for gRPC-web's 5-byte header and custom socket headers
- [ ] Mark `application/x-protobuf`, `application/protobuf` and `application/grpc` bodies as "proto, no rule"
- [ ] Show unmatched payloads as hex

**Generator (`Sources/CerebroProtoGenerator/`, `Plugins/CerebroProtoPlugin/`)**
- [ ] Generator executable: reads `traffic_map.json` and `.pb.swift` files, writes `ProtoRule.generated`, fails on an unknown name
- [ ] Generated code compiles in every channel, because `ProtoRule` is in `CerebroProto` for SPM and the XCFramework but in `Cerebro` for the Pod
- [ ] Build-tool plugin that runs it
- [ ] Add both targets, the `CerebroProtoPlugin` product and `CerebroProtoGeneratorTests` to `Package.swift`
- [ ] `Scripts/build-generator.sh`, producing `cerebro-proto-gen`

**Distribution**
- [ ] Keep the binary in the pod for a Run Script phase
- [ ] Attach the binary to each GitHub Release in `release.yml`
- [ ] Pass `-skipPackagePluginValidation` in CI
- [ ] README instructions for both the plugin and the Run Script phase

**Example**
- [ ] Add a generated `.pb.swift` message, since the generator resolves names by scanning `.pb.swift` files
- [ ] Apply `traffic_map.json` through the plugin, plus one rule in code, so both paths are tested

**Dashboard (`Sources/Cerebro/UI/`)**
- [ ] Collapsible JSON tree in the Log Inspector
- [ ] Proto Config tab: active mappings, URL matcher → message type, with their source and match counts
- [ ] Hide the tab when no proto decoder is registered

**Console**
- [ ] Decoded proto appears when logging is set to full

## Acceptance criteria

1. A rule in code and a rule in `traffic_map.json` both decode the Example app's protobuf traffic.
2. Code rules win over file rules, and the first matching rule wins.
3. A name in `traffic_map.json` that matches no type fails the build.
4. A gRPC-web body and a framed socket message decode after their prefix is stripped.
5. A protobuf content type with no rule shows as "proto, no rule", and unmatched payloads show as hex.
6. Binary socket frames decode through the same rules.
7. Decoded bodies show as a collapsible tree in the Log Inspector.
8. The Proto Config tab lists each rule's matcher, message type, source and match count.
9. The Proto Config tab is hidden in an app with no proto decoder registered.
10. The generator runs through the plugin for SPM and through the binary in a Run Script phase.
11. An app that links only `Cerebro` doesn't link SwiftProtobuf.
12. The `build-and-test` skill passes in all channels.

## Test checklist

**Unit**
- [ ] Matching by host, path, path prefix, regex and method
- [ ] Rule order
- [ ] Prefix stripping
- [ ] Content-type detection
- [ ] Generator: parsing, name resolution, unknown names, `version` handling

**Integration**
- [ ] A real message encoded and decoded through the pipeline
- [ ] The plugin in the Example app's build

**Manual**
- [ ] Tree interaction and the Proto Config tab
- [ ] Run Script phase in a Pod-based and an XCFramework-based app

