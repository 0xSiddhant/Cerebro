import Foundation

/// One request as captured, before redaction. Nothing outside the pipeline ever sees this.
struct RawExchange: Sendable {
    let id: UUID
    let request: URLRequest
    let requestBody: RawBody
    let response: URLResponse?
    let responseBody: RawBody?
    let error: (any Error)?
    let metrics: URLSessionTaskMetrics?
    let startDate: Date
    let endDate: Date
}
