import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// One line of the System Info tab.
struct SystemInfoRow: Equatable {
    let title: String
    let value: String
}

/// One group of lines on the System Info tab.
struct SystemInfoSection: Equatable {
    let title: String
    let rows: [SystemInfoRow]
    var footer: String?
}

/// What the System Info tab shows: the network the device is on, how the connection has been
/// performing, what the session has moved, and the downloads still running.
@MainActor
final class SystemInfoViewModel {
    private(set) var sections: [SystemInfoSection] = []

    /// Called after `sections` changes.
    var onChange: (() -> Void)?

    private let sources: DashboardSources
    private var info: SystemInfo?
    private var quality = ConnectionQuality(recent: [])
    private var totals = SessionTotals()
    private var downloads: [DownloadProgress] = []
    private var updates: [Task<Void, Never>] = []

    init(sources: DashboardSources) {
        self.sources = sources
        refresh()
    }

    deinit {
        updates.forEach { $0.cancel() }
    }

    /// Every source already publishes in batches, so each batch is one refresh.
    func startObserving() {
        guard updates.isEmpty else { return }
        updates = [
            Task { [weak self, sources] in
                for await info in await sources.systemInfo.updates() {
                    self?.info = info
                    self?.refresh()
                }
            },
            Task { [weak self, sources] in
                for await transactions in await sources.store.updates() {
                    let totals = await sources.store.totals
                    self?.quality = ConnectionQuality(recent: transactions)
                    self?.totals = totals
                    self?.refresh()
                }
            },
            Task { [weak self, sources] in
                for await downloads in await sources.downloads.updates() {
                    self?.downloads = downloads
                    self?.refresh()
                }
            },
        ]
    }

    private func refresh() {
        let latest = Self.sections(info: info, quality: quality, totals: totals, downloads: downloads)
        guard latest != sections else { return }
        sections = latest
        onChange?()
    }

    static func sections(
        info: SystemInfo?,
        quality: ConnectionQuality,
        totals: SessionTotals,
        downloads: [DownloadProgress]
    ) -> [SystemInfoSection] {
        let sections = [
            info.map { SystemInfoSection(title: "Connection", rows: connection($0)) },
            info.map { SystemInfoSection(title: "Addresses", rows: addresses($0)) },
            qualitySection(quality),
            SystemInfoSection(
                title: "Session totals",
                rows: [
                    SystemInfoRow(title: "Requests", value: String(totals.requestCount)),
                    SystemInfoRow(title: "Sent", value: DisplayFormat.bytes(totals.bytesSent)),
                    SystemInfoRow(title: "Received", value: DisplayFormat.bytes(totals.bytesReceived)),
                ]
            ),
            SystemInfoSection(title: "By host", rows: totals.byHost.map(row)),
            SystemInfoSection(title: "By connection type", rows: totals.byConnectionType.map(row)),
            SystemInfoSection(title: "Active downloads", rows: downloads.map(row)),
        ]
        return sections.compactMap { $0 }.filter { !$0.rows.isEmpty }
    }

    private static func connection(_ info: SystemInfo) -> [SystemInfoRow] {
        [
            SystemInfoRow(title: "Status", value: name(of: info.status)),
            info.connectionType.map { SystemInfoRow(title: "Type", value: name(of: $0)) },
            info.cellularGeneration.map { SystemInfoRow(title: "Cellular generation", value: $0) },
            SystemInfoRow(title: "Low Data Mode", value: info.isLowDataMode ? "On" : "Off"),
            SystemInfoRow(title: "Expensive connection", value: info.isExpensive ? "Yes" : "No"),
            SystemInfoRow(title: "VPN", value: info.isVPNActive ? "Connected" : "Not detected"),
            SystemInfoRow(title: "Proxy", value: info.isProxyActive ? "On" : "Not detected"),
        ]
        .compactMap { $0 }
    }

    private static func addresses(_ info: SystemInfo) -> [SystemInfoRow] {
        let local = info.addresses.map { address in
            let interface = address.interface == "pdp_ip0" ? "Cellular" : "Wi-Fi"
            return SystemInfoRow(title: "\(interface) \(address.isIPv6 ? "IPv6" : "IPv4")", value: address.address)
        }
        return local + [SystemInfoRow(title: "Public IP", value: text(of: info.publicIP))]
    }

    private static func qualitySection(_ quality: ConnectionQuality) -> SystemInfoSection {
        let rows = [
            quality.latency.map { SystemInfoRow(title: "Latency", value: DisplayFormat.duration($0)) },
            quality.connect.map { SystemInfoRow(title: "Connect", value: DisplayFormat.duration($0)) },
            quality.tls.map { SystemInfoRow(title: "TLS", value: DisplayFormat.duration($0)) },
            quality.throughput.map { SystemInfoRow(title: "Throughput", value: DisplayFormat.rate($0)) },
        ]
        .compactMap { $0 }
        guard !rows.isEmpty else {
            return SystemInfoSection(
                title: "Connection quality", rows: [SystemInfoRow(title: "No requests yet", value: "—")])
        }
        let requests = quality.sampleCount == 1 ? "the last request" : "the last \(quality.sampleCount) requests"
        return SystemInfoSection(title: "Connection quality", rows: rows, footer: "Averaged over \(requests).")
    }

    private static func row(for group: SessionTotals.Group) -> SystemInfoRow {
        let sent = DisplayFormat.bytes(group.bytesSent)
        let received = DisplayFormat.bytes(group.bytesReceived)
        return SystemInfoRow(title: group.name, value: "↑ \(sent)  ↓ \(received)")
    }

    private static func row(for download: DownloadProgress) -> SystemInfoRow {
        let name = download.url.map { $0.lastPathComponent.isEmpty ? $0.host ?? "Download" : $0.lastPathComponent }
        var value = DisplayFormat.bytes(download.bytesReceived)
        if let expected = download.expectedBytes, let fraction = download.fractionCompleted {
            value += " of \(DisplayFormat.bytes(expected)) (\(Int((fraction * 100).rounded(.down)))%)"
        }
        return SystemInfoRow(title: name ?? "Download", value: value)
    }

    private static func name(of status: SystemInfo.Status) -> String {
        switch status {
        case .online: return "Online"
        case .offline: return "Offline"
        case .requiresConnection: return "Requires connection"
        }
    }

    private static func name(of type: SystemInfo.ConnectionType) -> String {
        switch type {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        case .wired: return "Wired"
        case .other: return "Other"
        }
    }

    private static func text(of publicIP: SystemInfo.PublicIP) -> String {
        switch publicIP {
        case .off: return "Off"
        case .loading: return "Looking up…"
        case .address(let address): return address
        case .unavailable: return "Unavailable"
        }
    }
}
