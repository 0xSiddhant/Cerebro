import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// One section of the Log Inspector.
struct InspectorSection: Equatable {
    let title: String
    let rows: [InspectorRow]
}

/// One row of the Log Inspector. A row with a body opens it.
struct InspectorRow: Equatable {
    let title: String
    let value: String
    var body: CapturedBody?
}

/// Lays one transaction out as sections, leaving out anything it doesn't have.
@MainActor
final class LogInspectorViewModel {
    let title: String
    let sections: [InspectorSection]

    init(transaction: HTTPTransaction) {
        title = transaction.request.url?.lastPathComponent ?? transaction.request.method
        let candidates = [
            InspectorSection(title: "Overview", rows: Self.overview(of: transaction)),
            InspectorSection(title: "Request headers", rows: Self.rows(transaction.request.headers)),
            InspectorSection(title: "Query parameters", rows: Self.rows(transaction.request.queryParameters)),
            InspectorSection(title: "Request body", rows: Self.bodyRows(transaction.request.body)),
            InspectorSection(title: "Response headers", rows: Self.rows(transaction.response?.headers ?? [])),
            InspectorSection(title: "Response body", rows: Self.bodyRows(transaction.response?.body)),
            InspectorSection(title: "Timing", rows: Self.timing(of: transaction)),
            InspectorSection(title: "Size", rows: Self.size(of: transaction)),
            InspectorSection(title: "Connection", rows: Self.connection(of: transaction)),
        ]
        sections = candidates.filter { !$0.rows.isEmpty }
    }

    private static func rows(_ fields: [NamedValue]) -> [InspectorRow] {
        fields.map { InspectorRow(title: $0.name, value: $0.value) }
    }

    private static func row(_ title: String, _ value: String?) -> InspectorRow? {
        value.map { InspectorRow(title: title, value: $0) }
    }

    private static func overview(of transaction: HTTPTransaction) -> [InspectorRow] {
        [
            row("URL", transaction.request.url?.absoluteString),
            row("Method", transaction.request.method),
            row("Status", transaction.response.map { String($0.statusCode) }),
            row("MIME type", transaction.response?.mimeType),
            row("Error", transaction.failure.map { "\($0.description) (\($0.domain) \($0.code))" }),
        ]
        .compactMap { $0 }
    }

    private static func bodyRows(_ body: CapturedBody?) -> [InspectorRow] {
        guard let body else { return [] }
        return [
            InspectorRow(
                title: summary(of: body),
                value: DisplayFormat.bytes(Int64(body.byteCount)),
                body: body.data == nil ? nil : body
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
        let stages: [(String, TimeInterval?)] = [
            ("DNS", timing.dns),
            ("Connect", timing.connect),
            ("TLS", timing.tls),
            ("Request sent", timing.requestSent),
            ("First byte", timing.firstByte),
            ("Total", timing.total),
        ]
        return stages.compactMap { title, value in row(title, value.map(DisplayFormat.duration)) }
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
            row("Reused connection", yesOrNo(connection.isReused)),
            row("Cellular", yesOrNo(connection.isCellular)),
            row("Expensive", yesOrNo(connection.isExpensive)),
            row("Low Data Mode", yesOrNo(connection.isConstrained)),
        ]
        .compactMap { $0 }
    }

    private static func address(_ address: String?, _ port: Int?) -> String? {
        guard let address else { return nil }
        return port.map { "\(address):\($0)" } ?? address
    }

    private static func yesOrNo(_ value: Bool) -> String {
        value ? "Yes" : "No"
    }
}
