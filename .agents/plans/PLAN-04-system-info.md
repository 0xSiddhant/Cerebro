# PLAN-04 — System info and export

## Goal

Show the network context a failure happened in, using only what iOS exposes publicly, and let developers share what they captured as cURL, raw JSON or HAR.

## Gate

PLAN-03 merged. Single PR on `plan/4-system-info`.

## Scope

**In:** network info (path, interfaces, cellular generation, VPN and proxy, opt-in public IP), connection quality, session byte totals, download progress, the System Info tab, and sharing as cURL, raw JSON or HAR.

**Out:** signal strength, carrier name and Wi-Fi name. Device-wide traffic counters.

## Decisions & reasoning

### Only public APIs

| Field | Included | Source or reason |
|---|---|---|
| Status (online, offline, requires connection) | Yes | `NWPathMonitor` |
| Connection type (Wi-Fi, cellular, wired) | Yes | `NWPathMonitor` |
| Low Data Mode, expensive connection | Yes | `NWPathMonitor` |
| Cellular generation (4G, 5G) | Yes | CoreTelephony radio access technology |
| Local IP, IPv4 and IPv6 (`en0`, `pdp_ip0`) | Yes | POSIX `getifaddrs` |
| Public IP | Opt-in, off by default | A call to an external service; that call is excluded from the logs |
| Port, remote IP, HTTP version, TLS version | Yes, per request | Request metrics |
| VPN or proxy active | Yes | System proxy settings and interface names |
| Signal strength | No | No public API; `NEHotspotNetwork.fetchCurrent` returns a dummy value to apps without the hotspot-helper privilege |
| Carrier name | No | Deprecated since iOS 16 |
| Wi-Fi name (SSID) | No | Needs an extra entitlement and location permission in the host app |

### Connection quality replaces network strength

iOS has no signal-strength API. Connection quality means latency, connect and TLS time, and throughput per request, with a rolling average on the tab.

### Totals sum captured requests

Session totals are the sum of captured requests, from metrics. Device interface counters were rejected because they include traffic from every app on the phone.

### Downloads keep metadata only

Download tasks and image loaders that use URLSession, like Kingfisher or SDWebImage, record size, duration, throughput and MIME type. In-flight downloads show live progress. Bodies are not stored.

### Live numbers are batched, and exports stay off the main thread

Download progress and session totals change constantly during a transfer, so they follow PLAN-01's batched updates. A HAR export can cover a whole session, so exports build on a background queue.

### Export is safe by construction

Redaction runs before storage, so exports never hold a raw value. Export still shows a warning before sharing.

## Public API

| API | Purpose | Notes |
|---|---|---|
| Public IP setting | Enables the lookup | Off by default; the only data that leaves the device |

## Task checklist

**Metrics (`Sources/CerebroCore/Metrics/`)**
- [ ] `NWPathMonitor` status, connection type, Low Data Mode and expensive connection
- [ ] Cellular generation through CoreTelephony
- [ ] Local IPv4 and IPv6 through `getifaddrs`, with unsafe pointers only at that boundary
- [ ] VPN or proxy detection
- [ ] Opt-in public IP lookup, excluded from the logs
- [ ] Connection quality per request, with a rolling average
- [ ] Session totals sent and received, by host and by connection type
- [ ] Download size, duration, throughput, MIME type and live progress

**Export (`Sources/CerebroCore/Store/`)**
- [ ] Copy a request as cURL
- [ ] Export raw JSON payloads
- [ ] Export the whole session as HAR
- [ ] Build every export on a background queue

**Dashboard (`Sources/Cerebro/UI/`)**
- [ ] System Info tab: connection status and type, interfaces and IPs, connection quality, session byte totals, with batched updates
- [ ] Share from the Log Inspector through the share sheet, with the warning first

**Documentation**
- [ ] Update `README.md` feature summary and link to the guide
- [ ] Update `docs/GUIDE.md` with System Info fields, public-IP opt-in behavior, download metadata, and cURL/JSON/HAR export instructions

**Packaging**
- [ ] Add the new system frameworks to the `Core` subspec, and update `CerebroCore`'s dependencies in `.agents/context/architecture.md`

## Acceptance criteria

1. The System Info tab shows every included field, and none of the excluded ones.
2. With the public IP setting off, no external call is made. With it on, the call is absent from the logs.
3. Connection quality updates per request, with a rolling average.
4. Session totals break down by host and by connection type, and match the captured requests.
5. An in-flight download shows live progress, and its body is not stored.
6. A request copies as a working cURL command, and a session exports as valid HAR.
7. A redacted value never appears in any export.
8. Every export shows a warning before sharing.
9. Live download progress and totals update in batches, and a large export doesn't block the main thread.
10. The README and guide accurately describe the System Info tab, opt-in lookup, and export behavior.
11. The `build-and-test` skill passes in all channels.

## Test checklist

**Unit**
- [ ] Rolling average and totals
- [ ] cURL, raw JSON and HAR output, including redacted values
- [ ] `getifaddrs` parsing

**Integration**
- [ ] Public IP call excluded from the logs
- [ ] Download progress and metadata
- [ ] A full-session export runs off the main thread

**Manual, on a device**
- [ ] Wi-Fi to cellular changes, Low Data Mode, cellular generation, VPN and proxy
