import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// The System Info tab's pages, in the order the control shows them.
enum SystemInfoTab: Int, CaseIterable {
    case network
    case traffic
    case device

    var title: String {
        switch self {
        case .network: return "Network"
        case .traffic: return "Traffic"
        case .device: return "Device"
        }
    }
}

/// One line of the System Info tab. `symbol` names an SF Symbol.
struct SystemInfoRow: Equatable {
    let title: String
    let value: String
    var symbol: String?
}

/// One group of lines on the System Info tab.
struct SystemInfoSection: Equatable {
    let title: String
    let rows: [SystemInfoRow]
    var footer: String?
}

/// The card at the top of the tab.
struct SystemInfoSummary: Equatable {
    enum Tone: Equatable {
        case good
        case warning
        case bad
        case unknown
    }

    let symbol: String
    let tone: Tone
    let title: String
    let detail: String

    /// Things worth a second look, such as a VPN, shown only while they apply.
    let badges: [String]
}

/// What the System Info tab shows: the network the device is on, what the session has moved and how
/// fast, and the app and device themselves.
@MainActor
final class SystemInfoViewModel {
    private(set) var summary = SystemInfoViewModel.summary(of: nil)

    /// Called after the summary or any page changes.
    var onChange: (() -> Void)?

    private let sources: DashboardSources
    private let environment: AppEnvironment
    private var pages: [SystemInfoTab: [SystemInfoSection]] = [:]
    private var info: SystemInfo?
    private var quality = ConnectionQuality(recent: [])
    private var totals = SessionTotals()
    private var downloads: [DownloadProgress] = []
    private var updates: [Task<Void, Never>] = []

    init(sources: DashboardSources, environment: AppEnvironment = .current) {
        self.sources = sources
        self.environment = environment
        refresh()
    }

    deinit {
        updates.forEach { $0.cancel() }
    }

    func sections(for tab: SystemInfoTab) -> [SystemInfoSection] {
        pages[tab] ?? []
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
        let latest: [SystemInfoTab: [SystemInfoSection]] = [
            .network: Self.network(info),
            .traffic: Self.traffic(quality: quality, totals: totals, downloads: downloads),
            .device: Self.device(environment),
        ]
        let latestSummary = Self.summary(of: info)
        guard latest != pages || latestSummary != summary else { return }
        pages = latest
        summary = latestSummary
        onChange?()
    }

}

// MARK: - Summary

extension SystemInfoViewModel {

    static func summary(of info: SystemInfo?) -> SystemInfoSummary {
        guard let info else {
            return SystemInfoSummary(
                symbol: "network", tone: .unknown, title: "Checking the network…", detail: "", badges: [])
        }
        let badges = [
            info.isVPNActive ? "VPN" : nil,
            info.isProxyActive ? "Proxy" : nil,
            info.isLowDataMode ? "Low Data Mode" : nil,
        ]
        .compactMap { $0 }
        let type = [info.connectionType.map(name), info.cellularGeneration].compactMap { $0 }.joined(separator: " · ")
        switch info.status {
        case .online:
            return SystemInfoSummary(
                symbol: symbol(for: info.connectionType), tone: .good, title: "Online", detail: type, badges: badges)
        case .requiresConnection:
            return SystemInfoSummary(
                symbol: "exclamationmark.triangle.fill",
                tone: .warning,
                title: "Requires connection",
                detail: "The network needs something first, such as a VPN to connect.",
                badges: badges
            )
        case .offline:
            return SystemInfoSummary(
                symbol: "wifi.slash", tone: .bad, title: "Offline", detail: "No network connection.", badges: badges)
        }
    }

    private static func symbol(for type: SystemInfo.ConnectionType?) -> String {
        switch type {
        case .wifi: return "wifi"
        case .cellular: return "antenna.radiowaves.left.and.right"
        case .wired: return "cable.connector"
        case .other, nil: return "network"
        }
    }

    // MARK: - Network

    static func network(_ info: SystemInfo?) -> [SystemInfoSection] {
        guard let info else { return [] }
        let connection = [
            info.connectionType.map { SystemInfoRow(title: "Type", value: name(of: $0), symbol: symbol(for: $0)) },
            info.cellularGeneration.map {
                SystemInfoRow(title: "Cellular generation", value: $0, symbol: "cellularbars")
            },
            SystemInfoRow(title: "Low Data Mode", value: info.isLowDataMode ? "On" : "Off", symbol: "leaf"),
            SystemInfoRow(
                title: "Metered connection", value: info.isExpensive ? "Yes" : "No", symbol: "dollarsign.circle"),
            SystemInfoRow(title: "VPN", value: info.isVPNActive ? "Connected" : "Not detected", symbol: "lock.shield"),
            SystemInfoRow(
                title: "Proxy", value: info.isProxyActive ? "On" : "Not detected",
                symbol: "arrow.triangle.branch"),
        ]
        .compactMap { $0 }
        return [
            SystemInfoSection(
                title: "Connection",
                rows: connection,
                footer: "Metered means cellular or a personal hotspot. VPN and proxy come from the system's settings."
            ),
            SystemInfoSection(title: "IP addresses", rows: addresses(info), footer: publicIPFooter(info.publicIP)),
        ]
    }

    /// One row per interface and family, because a device often has several IPv6 addresses.
    private static func addresses(_ info: SystemInfo) -> [SystemInfoRow] {
        var titles: [String] = []
        var values: [String: [String]] = [:]
        for address in info.addresses {
            let interface = address.interface == "pdp_ip0" ? "Cellular" : "Wi-Fi"
            let title = "\(interface) \(address.isIPv6 ? "IPv6" : "IPv4")"
            if values[title] == nil {
                titles.append(title)
            }
            values[title, default: []].append(address.address)
        }
        let local = titles.map {
            SystemInfoRow(title: $0, value: (values[$0] ?? []).joined(separator: "\n"), symbol: "number")
        }
        return local + [SystemInfoRow(title: "Public IP", value: text(of: info.publicIP), symbol: "globe")]
    }

    private static func publicIPFooter(_ publicIP: SystemInfo.PublicIP) -> String? {
        publicIP == .off
            ? "The public IP is off. Start Cerebro with isPublicIPLookupEnabled to look it up at api.ipify.org." : nil
    }

    // MARK: - Traffic

    static func traffic(
        quality: ConnectionQuality,
        totals: SessionTotals,
        downloads: [DownloadProgress]
    ) -> [SystemInfoSection] {
        let sections = [
            SystemInfoSection(title: "Downloads in progress", rows: downloads.map(row)),
            performance(quality),
            SystemInfoSection(
                title: "This session",
                rows: [
                    SystemInfoRow(title: "Requests", value: String(totals.requestCount), symbol: "number"),
                    SystemInfoRow(title: "Sent", value: DisplayFormat.bytes(totals.bytesSent), symbol: "arrow.up"),
                    SystemInfoRow(
                        title: "Received", value: DisplayFormat.bytes(totals.bytesReceived), symbol: "arrow.down"),
                ],
                footer: "HTTP requests since Cerebro started. Sockets aren't counted."
            ),
            SystemInfoSection(title: "By host", rows: totals.byHost.map(row)),
            SystemInfoSection(title: "By connection", rows: totals.byConnectionType.map(row)),
        ]
        return sections.filter { !$0.rows.isEmpty }
    }

    /// A response time under this reads as good, and under `fairResponseTime` as fair.
    static let goodResponseTime: TimeInterval = 0.3
    static let fairResponseTime: TimeInterval = 1

    /// iOS has no signal-strength API, so this says how the app's own requests have been doing.
    private static func performance(_ quality: ConnectionQuality) -> SystemInfoSection {
        guard let latency = quality.latency else {
            return SystemInfoSection(
                title: "Performance",
                rows: [SystemInfoRow(title: "No requests yet", value: "—", symbol: "speedometer")],
                footer: "Make a request in your app to see how the connection is doing."
            )
        }
        let rating = latency < goodResponseTime ? "Good" : latency < fairResponseTime ? "Fair" : "Slow"
        let rows = [
            SystemInfoRow(title: "Overall", value: rating, symbol: "speedometer"),
            SystemInfoRow(title: "Server response time", value: DisplayFormat.duration(latency), symbol: "timer"),
            quality.connect.map {
                SystemInfoRow(title: "Connection setup", value: DisplayFormat.duration($0), symbol: "link")
            },
            quality.throughput.map {
                SystemInfoRow(title: "Download speed", value: DisplayFormat.rate($0), symbol: "arrow.down.circle")
            },
        ]
        .compactMap { $0 }
        let requests = quality.sampleCount == 1 ? "last request" : "last \(quality.sampleCount) requests"
        return SystemInfoSection(
            title: "Performance",
            rows: rows,
            footer: """
                Averages over your app's \(requests). Response time is how long a server took to start answering. \
                Connection setup counts only requests that opened a new connection, and download speed only \
                responses of 64 KB or more.
                """
        )
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
        return SystemInfoRow(title: name ?? "Download", value: value, symbol: "arrow.down.circle")
    }

    // MARK: - Device

    static func device(_ environment: AppEnvironment) -> [SystemInfoSection] {
        let version = [environment.version, environment.build.map { "(\($0))" }].compactMap { $0 }
        let app = [
            environment.appName.map { SystemInfoRow(title: "Name", value: $0, symbol: "app") },
            version.isEmpty
                ? nil : SystemInfoRow(title: "Version", value: version.joined(separator: " "), symbol: "tag"),
            environment.bundleIdentifier.map { SystemInfoRow(title: "Bundle ID", value: $0, symbol: "shippingbox") },
            environment.minimumSystemVersion.map {
                SystemInfoRow(title: "Minimum iOS", value: $0, symbol: "arrow.down.to.line")
            },
        ]
        .compactMap { $0 }
        let model = environment.isSimulator ? "\(environment.model) (Simulator)" : environment.model
        let device = [
            SystemInfoRow(title: "Model", value: model, symbol: "iphone"),
            environment.modelIdentifier.map { SystemInfoRow(title: "Identifier", value: $0, symbol: "barcode") },
            SystemInfoRow(title: "System", value: environment.system, symbol: "gearshape"),
            SystemInfoRow(
                title: "Memory", value: DisplayFormat.bytes(Int64(clamping: environment.memoryBytes)),
                symbol: "memorychip"),
            SystemInfoRow(title: "Processor cores", value: String(environment.processorCount), symbol: "cpu"),
            SystemInfoRow(
                title: "Low Power Mode", value: environment.isLowPowerModeOn ? "On" : "Off", symbol: "battery.50"),
            SystemInfoRow(title: "Locale", value: environment.locale, symbol: "character.bubble"),
            SystemInfoRow(title: "Time zone", value: environment.timeZone, symbol: "clock"),
        ]
        .compactMap { $0 }
        return [SystemInfoSection(title: "App", rows: app), SystemInfoSection(title: "Device", rows: device)]
            .filter { !$0.rows.isEmpty }
    }

    // MARK: - Names

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
