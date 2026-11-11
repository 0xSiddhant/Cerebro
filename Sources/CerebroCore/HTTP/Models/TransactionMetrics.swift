import Foundation
import Security

extension URLSessionTaskMetrics {
    /// Timings for the last network attempt, because a task can make several.
    var timing: TransactionTiming {
        let last = transactionMetrics.last
        return TransactionTiming(
            dns: Self.interval(last?.domainLookupStartDate, last?.domainLookupEndDate),
            connect: Self.interval(last?.connectStartDate, last?.connectEndDate),
            tls: Self.interval(last?.secureConnectionStartDate, last?.secureConnectionEndDate),
            requestSent: Self.interval(last?.requestStartDate, last?.requestEndDate),
            firstByte: Self.interval(last?.requestStartDate, last?.responseStartDate),
            receive: Self.interval(last?.responseStartDate, last?.responseEndDate),
            total: taskInterval.duration
        )
    }

    var connection: ConnectionDetails? {
        guard let last = transactionMetrics.last else { return nil }
        return ConnectionDetails(
            remoteAddress: last.remoteAddress,
            remotePort: last.remotePort,
            localAddress: last.localAddress,
            localPort: last.localPort,
            httpVersion: last.networkProtocolName,
            tlsVersion: Self.name(of: last.negotiatedTLSProtocolVersion),
            isReused: last.isReusedConnection,
            isCellular: last.isCellular,
            isExpensive: last.isExpensive,
            isConstrained: last.isConstrained
        )
    }

    /// Bytes across every attempt, since each one really crossed the wire.
    var size: TransferSize {
        var size = (sent: Int64(0), received: Int64(0), wireBody: Int64(0), decodedBody: Int64(0))
        for attempt in transactionMetrics {
            size.sent += attempt.countOfRequestHeaderBytesSent + attempt.countOfRequestBodyBytesSent
            size.received += attempt.countOfResponseHeaderBytesReceived + attempt.countOfResponseBodyBytesReceived
            size.wireBody += attempt.countOfResponseBodyBytesReceived
            size.decodedBody += attempt.countOfResponseBodyBytesAfterDecoding
        }
        return TransferSize(
            bytesSent: size.sent,
            bytesReceived: size.received,
            wireBodyBytes: size.wireBody,
            decodedBodyBytes: size.decodedBody
        )
    }

    /// Request body bytes across every attempt, for a body Cerebro never saw itself.
    var requestBodyBytes: Int64 {
        transactionMetrics.reduce(0) { $0 + $1.countOfRequestBodyBytesSent }
    }

    private static func interval(_ start: Date?, _ end: Date?) -> TimeInterval? {
        guard let start, let end else { return nil }
        return end.timeIntervalSince(start)
    }

    private static func name(of version: tls_protocol_version_t?) -> String? {
        switch version {
        case .TLSv12: return "TLS 1.2"
        case .TLSv13: return "TLS 1.3"
        case .none: return nil
        default: return "TLS (older than 1.2)"
        }
    }
}
