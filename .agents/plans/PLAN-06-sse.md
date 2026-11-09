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

Create one transaction when the response arrives, then update it with parsed events and its final outcome using the same ID. Show its live/completed state and event count in the HTTP list, and show events in a section of the Response page. Parsed events are the canonical stored representation: do not also buffer a second raw response body, add a separate dashboard tab, or display the stream as an ever-growing raw body.

### Parse incrementally according to SSE framing

Keep parser state across arbitrary URLSession data callbacks. Handle UTF-8 input, an initial BOM, CR, LF and CRLF line endings, comments, field parsing, multi-line `data`, and dispatch only at an event boundary when the event has a `data` field. Preserve the effective event ID and event type on captured events. Ignore `retry` for reconnect behavior: Cerebro observes the host app's connection and never owns it.

### Bound storage and work

Forward every response chunk to the app before handing it to a serial background parser. The aggregate budget for queued bytes, parser state, and retained event data is `bodyLimit`; cap stored events at 1,000 per stream. After either cap is reached, mark capture as truncated and stop retaining payloads while continuing to forward the response unchanged. Batch store and dashboard updates through the existing update path.

### Redact before publishing or persisting

Run each event's data through the existing body-processing and redaction pipeline before it reaches the live store. Apply configured JSON-key redaction to event metadata fields as well. A value that cannot be safely redacted is withheld, not exposed in a live update. Persist and export completed events only from the redacted transaction model; full console logging includes only redacted events after completion, while an active stream follows the existing in-flight persistence behavior.

### Keep the original HTTP view for other responses

Only final HTTP 200 responses with the `text/event-stream` media type use SSE parsing and the live event section. Other response bodies, request behavior, and capture semantics remain unchanged.

## Public API

| API | Purpose | Notes |
|---|---|---|
| `HTTPTransaction` lifecycle state and captured SSE events | Exposes live/completed status and parsed, redacted events to dashboard and package clients | Read-only captured data; no host-app setup or new configuration required |
| `CapturedSSEEvent` | Represents an event's ID, type, data, and receive time | Event data uses `CapturedBody` so withholding and truncation remain explicit |

## Task checklist

**Capture (`Sources/CerebroCore/HTTP/Capture/`)**
- [ ] Detect `text/event-stream` from the response media type, including case and parameters
- [ ] Forward response chunks first, then hand them in order to a bounded serial parser path
- [ ] Publish the initial transaction on response and finalize the same transaction on completion, cancellation, or error
- [ ] Keep non-SSE response handling unchanged

**Parser and pipeline (`Sources/CerebroCore/HTTP/Pipeline/`, `Sources/CerebroCore/Shared/Pipeline/`)**
- [ ] Add a testable incremental SSE parser with framing and field behavior from the WHATWG EventSource format
- [ ] Handle split UTF-8 sequences, BOM, CR/LF/CRLF, comments, multi-line data, IDs, event types, and incomplete input
- [ ] Process event data through existing redaction before it is sent to the store
- [ ] Enforce the per-stream byte and event caps without blocking or changing the host app's response stream

**Models and store (`Sources/CerebroCore/HTTP/Models/`, `Sources/CerebroCore/HTTP/Store/`)**
- [ ] Add public captured-event and transaction-lifecycle model data
- [ ] Add an ID-based transaction update path so an open request is updated rather than duplicated
- [ ] Preserve the existing request-count cap and batched observer notifications
- [ ] Extend PLAN-05 persistence to store completed redacted SSE events and decode pre-SSE records with safe defaults
- [ ] Include captured events in JSON and HAR exports from the redacted model
- [ ] Include completed, redacted events in `.full` console output without logging the live transaction repeatedly

**Dashboard (`Sources/Cerebro/UI/HTTPList/`, `Sources/Cerebro/UI/LogInspector/`)**
- [ ] Show an active/completed indicator and event count for SSE rows
- [ ] Show captured events on the Response page, including event type, ID when present, receive time, and data
- [ ] Refresh an open Log Inspector as events arrive, with updates batched and no main-thread parsing
- [ ] Open event data in the existing Body Viewer and display withheld/truncated states correctly

**Tests, documentation, and distribution**
- [ ] Add parser unit tests and local-server integration tests for chunked, long-lived SSE responses
- [ ] Test live store updates, finalization, cancellation, configured redaction, limits, and persisted-record compatibility
- [ ] Update `README.md` feature summary to mention live SSE capture and link to the guide for details
- [ ] Update `docs/GUIDE.md` to explain how SSE is detected and displayed, supported networking paths, event parsing, capture limits, and unsupported cases
- [ ] Update architecture and project-structure context
- [ ] Verify SPM, CocoaPods, and XCFramework builds without adding a dependency

## Acceptance criteria

1. A final HTTP 200 `text/event-stream` response through the supported `URLSession` capture path appears in the HTTP list while still open, without host-app changes.
2. Events appear in order while the connection is open; completion, cancellation, and errors update the same transaction rather than creating duplicate rows.
3. Parsing produces the same event boundaries and fields regardless of how bytes are split across URLSession callbacks, including CRLF boundaries and split UTF-8 characters.
4. Comments and `retry` fields do not become events, multi-line `data` fields join correctly, events without `data` are ignored, and incomplete fields do not leak into a later request.
5. Configured redaction is applied before event fields reach observers, UI, console logs, exports, or persistence; unredactable data is withheld.
6. Memory and queued work remain bounded by the configured body limit and 1,000 events per stream. Reaching a cap never changes the bytes or callbacks delivered to the host app.
7. Completed SSE transactions restore and export with their redacted events, and records persisted before this plan still decode correctly.
8. Non-SSE responses retain their current capture, storage, and display behavior.
9. `README.md` advertises live SSE capture and links to the guide; `docs/GUIDE.md` accurately documents behavior, limits, and unsupported paths.
10. The feature works consistently through SPM, CocoaPods, and XCFrameworks, and the `build-and-test` skill passes.

## Test checklist

**Unit**
- [ ] SSE parser fixtures for BOM, comments, all line endings, multi-line data, ID and event fields, invalid/repeated fields, and arbitrary chunk boundaries
- [ ] Per-stream byte/event limits and withheld/truncated event data
- [ ] Transaction store upsert, eviction, and batched live snapshots
- [ ] Persistence round-trip for SSE and backward-compatible decoding of older records
- [ ] Console summary/full output, including redacted event data only at `.full`

**Integration**
- [ ] A local server sends events over a held-open `text/event-stream` response; the app receives each chunk and the dashboard updates before close
- [ ] Stream close, cancellation, and transport failure finalize one transaction correctly
- [ ] Non-SSE chunked responses continue through the existing body path
- [ ] Configured JSON-key redaction is visible in neither live updates, console output, exports, nor persisted events

**Manual**
- [ ] Run a development-signed app against a controlled SSE endpoint and inspect events before and after the stream closes
- [ ] Exercise the feature through SPM, CocoaPods, and XCFramework client builds
