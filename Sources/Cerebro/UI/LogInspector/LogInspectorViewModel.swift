import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// The Log Inspector's pages, in the order the control shows them.
enum InspectorTab: Int, CaseIterable {
    case response
    case request
    case metrics

    var title: String {
        switch self {
        case .response: return "Response"
        case .request: return "Request"
        case .metrics: return "Metrics"
        }
    }
}

/// One figure in the summary at the top of the Log Inspector.
struct InspectorStat: Equatable {
    let title: String
    let value: String
}

/// What the request was and how it went.
struct InspectorSummary: Equatable {
    let method: String
    let url: String
    let status: String
    let outcome: TransactionOutcome
    let error: String?
    let stats: [InspectorStat]
}

/// One section of a Log Inspector page.
struct InspectorSection: Equatable {
    let title: String
    let rows: [InspectorRow]
}

/// Where a stage falls within the whole request, as fractions of it.
struct InspectorSpan: Equatable {
    let start: Double
    let length: Double
}

/// One row of the Log Inspector. A row with a body opens it.
struct InspectorRow: Equatable {
    let title: String
    let value: String
    var body: CapturedBody?
    var isBodyRow = false
    var preview: String?
    var span: InspectorSpan?
}

/// Lays one transaction out as a summary and pages, leaving out anything it doesn't have.
@MainActor
final class LogInspectorViewModel {
    let title: String
    let summary: InspectorSummary
    let request: CapturedRequest
    private let pages: [InspectorTab: [InspectorSection]]

    init(transaction: HTTPTransaction) {
        title = transaction.request.url?.lastPathComponent ?? transaction.request.method
        summary = Self.summary(of: transaction)
        request = transaction.request
        pages = [
            .response: Self.nonEmpty([
                InspectorSection(title: "Error", rows: Self.error(of: transaction)),
                InspectorSection(title: "Body", rows: Self.bodyRows(transaction.response?.body)),
                InspectorSection(title: "Headers", rows: Self.rows(transaction.response?.headers ?? [])),
            ]),
            .request: Self.nonEmpty([
                InspectorSection(title: "General", rows: Self.general(of: transaction)),
                InspectorSection(title: "Body", rows: Self.bodyRows(transaction.request.body)),
                InspectorSection(title: "Query", rows: Self.rows(transaction.request.queryParameters)),
                InspectorSection(title: "Headers", rows: Self.rows(transaction.request.headers)),
            ]),
            .metrics: Self.nonEmpty([
                InspectorSection(title: "Timing", rows: Self.timing(of: transaction)),
                InspectorSection(title: "Size", rows: Self.size(of: transaction)),
                InspectorSection(title: "Connection", rows: Self.connection(of: transaction)),
            ]),
        ]
    }

    func sections(for tab: InspectorTab) -> [InspectorSection] {
        pages[tab] ?? []
    }

    /// Drops empty sections, and says so when that leaves nothing, so a page is never blank.
    private static func nonEmpty(_ sections: [InspectorSection]) -> [InspectorSection] {
        let kept = sections.filter { !$0.rows.isEmpty }
        guard kept.isEmpty else { return kept }
        return [InspectorSection(title: "", rows: [InspectorRow(title: "Nothing captured", value: "—")])]
    }

    private static func summary(of transaction: HTTPTransaction) -> InspectorSummary {
        var stats: [InspectorStat] = []
        if let timing = transaction.timing {
            stats.append(InspectorStat(title: "Time", value: DisplayFormat.duration(timing.total)))
        }
        if let size = transaction.size {
            stats.append(InspectorStat(title: "Size", value: DisplayFormat.bytes(size.bytesReceived)))
        }
        if let type = transaction.response?.mimeType?.split(separator: "/").last {
            stats.append(InspectorStat(title: "Type", value: String(type)))
        }
        if let version = transaction.connection?.httpVersion {
            stats.append(InspectorStat(title: "Protocol", value: version))
        }
        return InspectorSummary(
            method: transaction.request.method,
            url: transaction.request.url?.absoluteString ?? "No URL",
            status: DisplayFormat.status(of: transaction),
            outcome: transaction.outcome,
            error: transaction.failure?.description,
            stats: stats
        )
    }

    private static func rows(_ fields: [NamedValue]) -> [InspectorRow] {
        fields.map { InspectorRow(title: $0.name, value: $0.value) }
    }

    private static func row(_ title: String, _ value: String?) -> InspectorRow? {
        value.map { InspectorRow(title: title, value: $0) }
    }

    private static func general(of transaction: HTTPTransaction) -> [InspectorRow] {
        [
            row("URL", transaction.request.url?.absoluteString),
            row("Method", transaction.request.method),
        ]
        .compactMap { $0 }
    }

    private static func error(of transaction: HTTPTransaction) -> [InspectorRow] {
        guard let failure = transaction.failure else { return [] }
        return [
            InspectorRow(title: "Description", value: failure.description),
            InspectorRow(title: "Domain", value: failure.domain),
            InspectorRow(title: "Code", value: String(failure.code)),
        ]
    }

    private static func bodyRows(_ body: CapturedBody?) -> [InspectorRow] {
        guard let body else { return [] }
        return [
            InspectorRow(
                title: summary(of: body),
                value: DisplayFormat.bytes(Int64(body.byteCount)),
                body: body.data == nil ? nil : body,
                isBodyRow: true,
                preview: body.data.flatMap(DisplayFormat.preview)
            )
        ]
    }

    private static func summary(of body: CapturedBody) -> String {
        var parts: [String] = []
        switch body.content {
        case .complete: parts.append("View body")
        case .truncated: parts.append("View start of body (truncated)")
        case .withheld: parts.append("Withheld, because it couldn't be redacted")
        case .notStored: parts.append("Not stored, because it's a download")
        }
        if let compression = body.compression {
            parts.append("\(compression.rawValue), \(body.isDecompressed ? "decompressed for display" : "shown raw")")
        }
        return parts.joined(separator: " · ")
    }

    private static func timing(of transaction: HTTPTransaction) -> [InspectorRow] {
        guard let timing = transaction.timing else { return [] }
        let dns = timing.dns ?? 0
        let connected = dns + (timing.connect ?? 0)
        return [
            stage("DNS", timing.dns, startingAt: 0, within: timing.total),
            stage("Connect", timing.connect, startingAt: dns, within: timing.total),
            stage("TLS", timing.tls, startingAt: connected - (timing.tls ?? 0), within: timing.total),
            stage("Request sent", timing.requestSent, startingAt: connected, within: timing.total),
            stage("First byte", timing.firstByte, startingAt: connected, within: timing.total),
            stage("Total", timing.total, startingAt: 0, within: timing.total),
        ]
        .compactMap { $0 }
    }

    private static func stage(
        _ title: String,
        _ duration: TimeInterval?,
        startingAt start: TimeInterval,
        within total: TimeInterval
    ) -> InspectorRow? {
        duration.map {
            InspectorRow(
                title: title,
                value: DisplayFormat.duration($0),
                span: span(from: start, lasting: $0, within: total)
            )
        }
    }

    /// Stages come from the last attempt and the total from the whole task, so this has to clamp.
    private static func span(
        from start: TimeInterval,
        lasting duration: TimeInterval,
        within total: TimeInterval
    ) -> InspectorSpan? {
        guard total > 0 else { return nil }
        let begin = min(max(start / total, 0), 1)
        return InspectorSpan(start: begin, length: min(max(duration / total, 0), 1 - begin))
    }

    private static func size(of transaction: HTTPTransaction) -> [InspectorRow] {
        guard let size = transaction.size else { return [] }
        return [
            row("Sent", DisplayFormat.bytes(size.bytesSent)),
            row("Received on the wire", DisplayFormat.bytes(size.bytesReceived)),
            row("Body on the wire", DisplayFormat.bytes(size.wireBodyBytes)),
            row("Body after decoding", DisplayFormat.bytes(size.decodedBodyBytes)),
            row("Encoding", transaction.response?.contentEncoding),
            row("Compression ratio", size.compressionRatio.map { String(format: "%.1fx", $0) }),
        ]
        .compactMap { $0 }
    }

    private static func connection(of transaction: HTTPTransaction) -> [InspectorRow] {
        guard let connection = transaction.connection else { return [] }
        return [
            row("Remote", address(connection.remoteAddress, connection.remotePort)),
            row("Local", address(connection.localAddress, connection.localPort)),
            row("HTTP version", connection.httpVersion),
            row("TLS version", connection.tlsVersion),
            row("Reused connection", connection.isReused ? "Yes" : "No"),
            row("Network", network(of: connection)),
        ]
        .compactMap { $0 }
    }

    private static func address(_ address: String?, _ port: Int?) -> String? {
        guard let address else { return nil }
        return port.map { "\(address):\($0)" } ?? address
    }

    private static func network(of connection: ConnectionDetails) -> String {
        var traits = [connection.isCellular ? "Cellular" : "Not cellular"]
        if connection.isExpensive { traits.append("Expensive") }
        if connection.isConstrained { traits.append("Low Data Mode") }
        return traits.joined(separator: ", ")
    }
}
