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

    /// What the Body Viewer is titled when this row opens it, if not the page's name.
    var bodyTitle: String?
    var preview: String?
    var span: InspectorSpan?
}

/// Lays one transaction out as a summary and pages, leaving out anything it doesn't have. An event
/// stream that's still open is followed in the store until it ends.
@MainActor
final class LogInspectorViewModel {
    let title: String
    let request: CapturedRequest
    private(set) var summary: InspectorSummary
    private(set) var transaction: HTTPTransaction

    /// Called after the transaction changes.
    var onChange: (() -> Void)?

    private var pages: [InspectorTab: [InspectorSection]]
    private let store: TransactionStore?
    private var updates: Task<Void, Never>?

    /// `store` is where an open event stream's updates come from. Without it the page never changes.
    init(transaction: HTTPTransaction, store: TransactionStore? = nil) {
        title = transaction.request.url?.lastPathComponent ?? transaction.request.method
        request = transaction.request
        summary = Self.summary(of: transaction)
        self.transaction = transaction
        pages = Self.pages(of: transaction)
        self.store = store
    }

    deinit {
        updates?.cancel()
    }

    /// Follows the store for as long as the request is open. A finished request never changes, so it
    /// observes nothing.
    func startObserving() {
        guard updates == nil, transaction.isOpen, let store else { return }
        updates = Task { [weak self, store] in
            for await transactions in await store.updates() {
                guard let self else { return }
                self.show(transactions)
                if !self.transaction.isOpen { return }
            }
        }
    }

    /// Takes the store's transactions. If this one is gone from them, the page keeps what it had.
    func show(_ transactions: [HTTPTransaction]) {
        guard let latest = transactions.last(where: { $0.id == transaction.id }), latest != transaction else {
            return
        }
        transaction = latest
        summary = Self.summary(of: latest)
        pages = Self.pages(of: latest)
        onChange?()
    }

    private static func pages(of transaction: HTTPTransaction) -> [InspectorTab: [InspectorSection]] {
        [
            .response: Self.nonEmpty([
                InspectorSection(title: "Error", rows: Self.error(of: transaction)),
                InspectorSection(title: "Body", rows: Self.bodyRows(transaction.response?.body)),
                InspectorSection(title: "Headers", rows: Self.rows(transaction.response?.headers ?? [])),
                // Last, so a stream of any length never pushes the headers out of reach.
                InspectorSection(
                    title: transaction.eventStream.map(Self.eventsTitle) ?? "",
                    rows: transaction.eventStream.map(Self.eventRows) ?? []
                ),
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
        if let stream = transaction.eventStream {
            stats.append(InspectorStat(title: "Stream", value: stream.state == .open ? "Live" : "Ended"))
            stats.append(InspectorStat(title: "Events", value: stream.eventCount.formatted()))
        } else if let type = transaction.response?.mimeType?.split(separator: "/").last {
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
                preview: DisplayFormat.preview(of: body)
            )
        ]
    }

    private static func eventsTitle(_ stream: CapturedEventStream) -> String {
        if stream.events.count < stream.eventCount {
            return "Events · newest \(stream.events.count.formatted()) of \(stream.eventCount.formatted())"
        }
        // Nothing was dropped from the list, so parsing stopped because events arrived too fast.
        return stream.isTruncated ? "Events · incomplete, they arrived too fast" : "Events"
    }

    private static func eventRows(_ stream: CapturedEventStream) -> [InspectorRow] {
        guard !stream.events.isEmpty else {
            return [InspectorRow(title: stream.state == .open ? "Waiting for events" : "No events", value: "—")]
        }
        return stream.events.map { event in
            var title = [event.type, event.id.map { "#\($0)" }, DisplayFormat.time(event.date)].compactMap { $0 }
            switch event.data.content {
            case .complete: break
            case .truncated: title.append("truncated")
            case .withheld: title.append("withheld, because it couldn't be redacted")
            case .notStored: title.append("not stored")
            }
            return InspectorRow(
                title: title.joined(separator: " · "),
                value: DisplayFormat.bytes(Int64(event.data.byteCount)),
                body: event.data.data?.isEmpty == false ? event.data : nil,
                isBodyRow: true,
                bodyTitle: "Event data",
                preview: DisplayFormat.preview(of: event.data)
            )
        }
    }

    private static func summary(of body: CapturedBody) -> String {
        var parts: [String] = []
        switch body.content {
        case .complete: parts.append("View body")
        case .truncated: parts.append("View start of body (truncated)")
        case .withheld: parts.append("Withheld, because it couldn't be redacted")
        case .notStored: parts.append("Not stored, because it's a download or background transfer")
        }
        if let compression = body.compression {
            parts.append("\(compression.rawValue), \(body.isDecompressed ? "decompressed for display" : "shown raw")")
        }
        if let decoding = DisplayFormat.decodingLabel(of: body) {
            parts.append(decoding)
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
            row("Throughput", transaction.throughput.map(DisplayFormat.rate)),
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
