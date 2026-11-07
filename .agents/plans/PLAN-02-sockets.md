# PLAN-02 — WebSockets, NWConnection and the Sockets tab

## Goal

Socket traffic becomes as visible as HTTP. `URLSessionWebSocketTask` is captured with no app changes, `NWConnection` through a wrapper, and any other engine through manual calls, all shown as a chat-style timeline.

## Gate

PLAN-01 merged. Single PR on `plan/2-sockets`.

## Scope

**In:** automatic `URLSessionWebSocketTask` hooks, `MonitoredNWConnection`, `ExternalNetworkBridge`, per-frame logging, connection events, the frame cap, and the Sockets tab.

**Out:** proto decoding of frames (PLAN-03 plugs into the same pipeline). Previous-session sockets (PLAN-05). WKWebView, AVPlayer and gRPC over SwiftNIO stay out of reach.

## Decisions & reasoning

### One capture path per source

| Source | How it's captured | Change needed in the app |
|---|---|---|
| `URLSessionWebSocketTask` | Hooks on its public `send`, `receive`, `resume`, `sendPing(pongReceiveHandler:)` and `cancel(with:reason:)` methods | None |
| `NWConnection` | `MonitoredNWConnection` wrapper: state changes, bytes, frames | Create the wrapper instead of `NWConnection` |
| Starscream, Socket.IO, other engines | `ExternalNetworkBridge` manual calls | One call per frame or event |

A developer-swapped `MonitoredWebSocketTask` was rejected because it forces call-site changes and makes Cerebro a production dependency. Fishhook on C symbols was rejected as unstable. Network.framework has no Objective-C methods to hook, so `NWConnection` needs a wrapper, and third-party engines bypass URLSession entirely.

The wrapper and the bridge are the only socket features that need code, against the zero-code-change priority. They exist because nothing automatic can reach that traffic, and both are additive: an app that skips them only loses that traffic.

### Hooks cover every connection event

`send` and `receive` can't see open, close, or ping and pong. So the hooks also cover the public `resume`, `sendPing(pongReceiveHandler:)` and `cancel(with:reason:)` methods. A close started by the server is read from `closeCode` and `closeReason` after a receive fails. Apps change nothing either way.

⚠️ Confirm in a spike that the hooks see both the completion-handler and `async` forms of `send` and `receive`. If the `async` forms slip past them, tell the owner before building on it, because that would leave `async` traffic uncaptured.

### `MonitoredNWConnection` lives in production code

Whenever Cerebro is off, it must be a zero-cost pass-through to the real `NWConnection`. No hooks run while Cerebro is off.

### Frames share the HTTP pipeline

Each frame's payload runs through the same decoders as HTTP bodies. Binary frames go through decompression and proto decoding, since that's where most unreadable payloads come from.

## Public API

| API | Purpose | Notes |
|---|---|---|
| `MonitoredNWConnection` | Wraps `NWConnection` | Pass-through while Cerebro is off |
| `ExternalNetworkBridge` | Manual logging for other socket engines | One call per frame or event |
| Socket frames per connection setting | Caps stored frames | Default 1,000, configurable |

## Task checklist

**Capture (`Sources/CerebroCore/Capture/`)**
- [ ] Spike: confirm the hooks see the completion-handler and `async` forms of `send` and `receive`
- [ ] `URLSessionWebSocketTask` hooks on `send`, `receive`, `resume`, `sendPing(pongReceiveHandler:)` and `cancel(with:reason:)`, installed at start only
- [ ] Read `closeCode` and `closeReason` after a receive fails, to record a close started by the server
- [ ] `MonitoredNWConnection`
- [ ] `ExternalNetworkBridge`

**Models and store (`Sources/CerebroCore/Models/`, `Sources/CerebroCore/Store/`)**
- [ ] Frame model: direction, type (text or binary), size, timestamp, decoded payload
- [ ] Connection event model: open, close (code and reason), ping and pong, state changes, errors
- [ ] Per-connection frame cap, and redaction before storage

**Pipeline (`Sources/CerebroCore/Pipeline/`)**
- [ ] Route frame payloads through the existing chain

**Dashboard (`Sources/Cerebro/UI/`)**
- [ ] Sockets tab: list of connections
- [ ] Chat-style frame timeline, with outgoing in blue and incoming in gray

**Example**
- [ ] Route the app's `NWConnection` traffic through `MonitoredNWConnection`

## Acceptance criteria

1. The Example app's WebSocket traffic appears with no change to its calling code.
2. Its `NWConnection` traffic appears through the wrapper, with state changes and bytes.
3. A manual `ExternalNetworkBridge` call appears in the same tab.
4. Each frame shows direction, type, size, timestamp and payload.
5. Open, close with code and reason, ping and pong, state changes and errors all appear as events.
6. Frame 1,001 on a connection evicts the oldest.
7. With Cerebro off, no hooks run and `MonitoredNWConnection` only forwards to the real connection.
8. A compressed binary frame shows decompressed.
9. The `build-and-test` skill passes in all channels.

## Test checklist

**Unit**
- [ ] Frame cap and eviction
- [ ] `ExternalNetworkBridge` events reach the store
- [ ] Pipeline handling of text, binary and compressed frames

**Integration**
- [ ] A local echo exchange through a `URLSessionWebSocketTask` is captured
- [ ] `MonitoredNWConnection` forwards correctly with Cerebro on and off

**Manual**
- [ ] Timeline colours and order in the Example app

