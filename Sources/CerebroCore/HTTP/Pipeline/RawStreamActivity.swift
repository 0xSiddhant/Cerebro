import Foundation

/// One thing that happened on an event stream, before the pipeline runs. These travel in order through
/// their own unbounded queue, so a stream's end can never be dropped or overtake its last bytes.
struct RawStreamActivity: Sendable {
    enum Content: Sendable {
        /// The response arrived. The exchange has no response body, error or metrics yet.
        case opened(RawExchange)

        /// Response bytes, which `backlog` counted and gets told about once they've been parsed.
        case chunk(Data, backlog: CaptureBacklog)

        /// Bytes arrived faster than they could be parsed and were dropped, so framing is lost.
        case overflowed

        /// Time to publish what has arrived since the last update, if anything has.
        case flush

        /// The stream ended, was cancelled or failed.
        case finished(RawExchange)
    }

    /// The transaction this belongs to.
    let id: UUID
    let content: Content
    let date: Date
}
