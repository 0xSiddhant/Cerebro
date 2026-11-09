# PLAN-06 — Server-Sent Events capture and live inspection

## Goal

Capture standard Server-Sent Events (SSE) responses made through the existing `URLSession` capture path and show their parsed events in the HTTP dashboard while the stream is open. SSE is a long-lived HTTP response, so waiting for completion can hide its traffic indefinitely; this plan makes it useful without requiring host-app code.

## Gate

PLAN-05 merged and `v1.0.0` released. Single PR on `plan/6-sse`.

## Scope

**In:** automatic detection of `text/event-stream`, bounded incremental parsing, live HTTP transaction updates, an event list in the Log Inspector, redaction, persistence and export of completed streams, documentation, and coverage in all three distribution channels.

**Out:** a client-side `EventSource` implementation, automatic reconnect or replay, custom networking stacks that bypass the existing capture path, and background-session capture beyond PLAN-05.

## Decisions & reasoning

### Reuse the existing HTTP capture path

Recognize final HTTP 200 responses with the `text/event-stream` media type from the existing `URLProtocol` path. This includes ordinary `URLSession` clients and third-party libraries using that path, without app changes. Do not add a second transport hook or promise capture for libraries that use another networking stack.

### Treat an SSE response as a live HTTP transaction

Create one transaction when the response arrives, then update it with parsed events and its final outcome using the same ID. Show its live/completed state and event count in the HTTP list, and show events as the last section of the Response page, after the headers, so a long stream never buries them. Parsed events are the canonical stored representation: do not also buffer a second raw response body, add a separate dashboard tab, or display the stream as an ever-growing raw body.

`CapturedResponse.endDate` stays non-optional, because making it optional after `v1.0.0` would be a breaking change. While a stream is open it holds the time data last arrived, and it becomes final when the stream ends.

The request-count cap still applies, and an open stream can be the oldest row, so it can be evicted first. An update for a transaction that has been evicted is ignored, never reinserted.

### Parse incrementally according to SSE framing

Keep parser state across arbitrary URLSession data callbacks. Handle UTF-8 input, an initial BOM, CR, LF and CRLF line endings, comments, field parsing, multi-line `data`, and dispatch only at an event boundary when the event has a `data` field. Preserve the effective event ID and event type on captured events. Ignore `retry` for reconnect behavior: Cerebro observes the host app's connection and never owns it.

### Bound storage and work

Forward every response chunk to the app before handing it to a serial background parser. Retained events are capped at 1,000 and at `bodyLimit` bytes per stream. At either cap the oldest events are dropped, as the Sockets timeline does, so a long-running feed always shows its newest events. The event count keeps counting every event, and the stream is marked truncated.

Bytes waiting for the parser and partial parser state are also bounded by `bodyLimit`. If they overflow, framing is lost, so parsing stops for that stream and it's marked truncated. In every case the response keeps reaching the app unchanged. Batch store and dashboard updates through the existing update path.

### The final state is never lost

Events and the stream's completion travel through one ordered path, so a stream can't finish before its last event is applied. That path doesn't use the request pipeline's `AsyncStream`, which keeps only the newest entries and could drop a completion, leaving a row live forever. As with sockets and `SocketBacklog`, only payload bytes are limited, and completion always gets through.

### Long-lived streams keep the existing timeout limit

Cerebro runs each request through its own session, whose idle timeout is the default 60 seconds. A timeout set on the `URLRequest` carries over, but one set on the app's `URLSessionConfiguration` never reaches a `URLProtocol`: a probe protocol saw a configuration value of 3600 arrive as 60. So a stream that stays quiet for 60 seconds can time out only because Cerebro is running, if the app set its timeout on the configuration. This plan documents that rather than changing it, because a longer inner timeout for requests sent with `Accept: text/event-stream` would remove a limit an app may rely on.

### No recurring work while the dashboard is closed

The trigger badge observes the store all the time and only counts requests, so event-only updates must not wake it. An open stream causes no recurring main-thread work while the dashboard is closed.

### Redact before publishing or persisting

Run each event's data through the existing body-processing and redaction pipeline before it reaches the live store. Event `id` and `event` values are plain text, so they follow the rule for socket event text: a value containing a configured key name becomes `[redacted]`. A value that cannot be safely redacted is withheld, not exposed in a live update. That includes data that looks like JSON but doesn't parse when `jsonKeys` is set, such as the `[DONE]` marker many streaming APIs send, and the guide says so.

Persist and export completed events only from the redacted transaction model. PLAN-05 saves only completed requests, so an open stream isn't saved, and one still open when the app exits isn't restored. Full console logging includes only redacted events after completion.

### Keep the original HTTP view for other responses

Only final HTTP 200 responses with the `text/event-stream` media type use SSE parsing and the live event section. Other response bodies, request behavior, and capture semantics remain unchanged.

## Public API

| API | Purpose | Notes |
|---|---|---|
| `HTTPTransaction` lifecycle state, total event count and captured SSE events | Exposes live/completed status, how many events arrived, and the retained, redacted events to dashboard and package clients | Read-only captured data; no host-app setup or new configuration required |
| `CapturedResponse.endDate` | Time data last arrived while a stream is open, and the final time after it ends | Stays non-optional, so this isn't a breaking change |
| `CapturedSSEEvent` | Represents an event's ID, type, data, and receive time | Event data uses `CapturedBody` so withholding and truncation remain explicit |

## Task checklist

**Capture (`Sources/CerebroCore/HTTP/Capture/`)**
- [ ] Detect `text/event-stream` from the response media type, including case and parameters
- [ ] Forward response chunks first, then hand them in order to a bounded serial parser path
- [ ] Send completion through that same ordered path, limiting only payload bytes so it's never dropped
- [ ] Publish the initial transaction on response and finalize the same transaction on completion, cancellation, or error
- [ ] Keep non-SSE response handling unchanged

**Parser and pipeline (`Sources/CerebroCore/HTTP/Pipeline/`, `Sources/CerebroCore/Shared/Pipeline/`)**
- [ ] Add a testable incremental SSE parser with framing and field behavior from the WHATWG EventSource format
- [ ] Handle split UTF-8 sequences, BOM, CR/LF/CRLF, comments, multi-line data, IDs, event types, and incomplete input
- [ ] Process event data through existing redaction before it is sent to the store
- [ ] Enforce the per-stream byte and event caps by dropping the oldest events and counting every event, without blocking or changing the host app's response stream

**Models and store (`Sources/CerebroCore/HTTP/Models/`, `Sources/CerebroCore/HTTP/Store/`)**
- [ ] Add public captured-event and transaction-lifecycle model data
- [ ] Add an ID-based transaction update path so an open request is updated rather than duplicated
- [ ] Keep `CapturedResponse.endDate` non-optional, holding the last received time until the stream ends, and correct the `HTTPTransaction` doc comment, which says finished
- [ ] Preserve the existing request-count cap and batched observer notifications
- [ ] Ignore an update for a transaction that has been evicted, never reinserting it
- [ ] Publish event-only updates without waking the trigger badge, which only needs requests added or removed
- [ ] Extend PLAN-05 persistence to store completed redacted SSE events and decode pre-SSE records with safe defaults
- [ ] Include captured events in JSON and HAR exports from the redacted model
- [ ] Include completed, redacted events in `.full` console output without logging the live transaction repeatedly

**Dashboard (`Sources/Cerebro/UI/HTTPList/`, `Sources/Cerebro/UI/LogInspector/`)**
- [ ] Show an active/completed indicator and event count for SSE rows
- [ ] Reconfigure a row when its content changes, because `HTTPListViewController` applies IDs only and an unchanged ID doesn't redraw
- [ ] Show captured events as the last section of the Response page, including event type, ID when present, receive time, and data
- [ ] Refresh an open Log Inspector as events arrive, following `SocketTimelineViewModel`'s store observation, with updates batched and no main-thread parsing
- [ ] Open event data in the existing Body Viewer and display withheld/truncated states correctly

**Tests, documentation, and distribution**
- [ ] Add parser unit tests and local-server integration tests for chunked, long-lived SSE responses
- [ ] Test live store updates, finalization, cancellation, configured redaction, limits, and persisted-record compatibility
- [ ] Add live SSE capture to the traffic listed in the `README.md` intro, and link to the guide for details
- [ ] Update `docs/GUIDE.md` to explain how SSE is detected and displayed, supported networking paths, event parsing, capture limits, the timeout limit for long-lived streams, the withheld `[DONE]` case, and unsupported cases
- [ ] Update architecture and project-structure context
- [ ] Verify SPM, CocoaPods, and XCFramework builds without adding a dependency

## Acceptance criteria

1. A final HTTP 200 `text/event-stream` response through the supported `URLSession` capture path appears in the HTTP list while still open, without host-app changes.
2. Events appear in order while the connection is open; completion, cancellation, and errors update the same transaction rather than creating duplicate rows. The row's state and event count update in place, and the final state is never lost, even under load.
3. Parsing produces the same event boundaries and fields regardless of how bytes are split across URLSession callbacks, including CRLF boundaries and split UTF-8 characters.
4. Comments and `retry` fields do not become events, multi-line `data` fields join correctly, events without `data` are ignored, and incomplete fields do not leak into a later request.
5. Configured redaction is applied before event fields reach observers, UI, console logs, exports, or persistence; unredactable data is withheld.
6. Memory and queued work remain bounded by the configured body limit and 1,000 events per stream. Reaching a cap keeps the newest events and the full event count, and never changes the bytes or callbacks delivered to the host app.
7. Completed SSE transactions restore and export with their redacted events, and records persisted before this plan still decode correctly.
8. Non-SSE responses retain their current capture, storage, and display behavior.
9. The `README.md` intro names live SSE capture and links to the guide; `docs/GUIDE.md` accurately documents behavior, limits including the timeout limit, and unsupported paths.
10. With the dashboard closed, an open stream causes no recurring main-thread work.
11. The feature works consistently through SPM, CocoaPods, and XCFrameworks, and the `build-and-test` skill passes.

## Test checklist

**Unit**
- [ ] SSE parser fixtures for BOM, comments, all line endings, multi-line data, ID and event fields, invalid/repeated fields, and arbitrary chunk boundaries
- [ ] Per-stream byte/event limits, with the oldest events dropped and every event counted, and withheld/truncated event data
- [ ] Transaction store upsert, eviction, updates for an evicted transaction, and batched live snapshots
- [ ] Event-only updates don't wake the trigger badge, and a changed row is reconfigured
- [ ] `id` and `event` values naming a key become `[redacted]`, and `[DONE]` is withheld when `jsonKeys` is set
- [ ] Persistence round-trip for SSE and backward-compatible decoding of older records
- [ ] Console summary/full output, including redacted event data only at `.full`

**Integration**
- [ ] A local server sends events over a held-open `text/event-stream` response; the app receives each chunk and the dashboard updates before close
- [ ] The same stream through `URLSession.bytes(for:)`, a delegate-based client, and a POST-started request
- [ ] Stream close, cancellation, and transport failure finalize one transaction correctly, including under a burst that overflows the queued-byte budget
- [ ] Non-SSE chunked responses continue through the existing body path
- [ ] Configured JSON-key redaction is visible in neither live updates, console output, exports, nor persisted events

**Manual**
- [ ] Run a development-signed app against a controlled SSE endpoint and inspect events before and after the stream closes
- [ ] Hold a stream idle past 60 seconds with the timeout set on the request, then on the configuration, and confirm the documented behavior
- [ ] Exercise the feature through SPM, CocoaPods, and XCFramework client builds
