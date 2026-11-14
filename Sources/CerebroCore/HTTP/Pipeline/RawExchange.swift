import Foundation

/// One request as captured, before redaction. Nothing outside the pipeline ever sees this.
struct RawExchange: Sendable {
    let id: UUID
    let request: URLRequest

    /// `nil` when the body exists but Cerebro never saw it, as with a background upload's file.
    let requestBody: RawBody?

    let response: URLResponse?
    let responseBody: RawBody?
    let error: (any Error)?
    let metrics: URLSessionTaskMetrics?
    let startDate: Date
    let endDate: Date

    /// Whether the response is a `text/event-stream`, whose events are captured in place of a body.
    var isEventStream = false
}
