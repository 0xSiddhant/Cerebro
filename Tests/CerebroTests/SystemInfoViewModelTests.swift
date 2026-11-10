import Foundation
import Testing
@testable import Cerebro

private let online = SystemInfo(
    status: .online,
    connectionType: .cellular,
    isLowDataMode: true,
    isExpensive: true,
    cellularGeneration: "5G",
    addresses: [
        InterfaceAddress(interface: "en0", address: "192.168.1.20", isIPv6: false),
        InterfaceAddress(interface: "en0", address: "2001:db8::1", isIPv6: true),
        InterfaceAddress(interface: "en0", address: "2001:db8::2", isIPv6: true),
        InterfaceAddress(interface: "pdp_ip0", address: "10.0.0.5", isIPv6: false),
    ],
    isVPNActive: true,
    isProxyActive: false,
    publicIP: .address("203.0.113.7")
)

private let environment = AppEnvironment(
    appName: "Shop",
    version: "2.1",
    build: "45",
    bundleIdentifier: "com.example.shop",
    minimumSystemVersion: "16.0",
    model: "iPhone",
    modelIdentifier: "iPhone17,3",
    system: "iOS 26.4",
    isSimulator: false,
    memoryBytes: 8_000_000_000,
    processorCount: 6,
    isLowPowerModeOn: true,
    locale: "en_IN",
    timeZone: "Asia/Kolkata"
)

private func request(received: Int64 = 4_000, firstByte: TimeInterval = 0.05) -> HTTPTransaction {
    HTTPTransaction(
        request: CapturedRequest(url: URL(string: "https://api.example.com/a"), method: "GET", startDate: Date()),
        timing: TransactionTiming(connect: 0.2, tls: 0.1, firstByte: firstByte, total: 2),
        connection: ConnectionDetails(isCellular: true),
        size: TransferSize(bytesSent: 1_000, bytesReceived: received, wireBodyBytes: 0, decodedBodyBytes: 0)
    )
}

@MainActor
private func traffic(
    _ transactions: [HTTPTransaction] = [],
    downloads: [DownloadProgress] = []
) async -> [SystemInfoSection] {
    let store = TransactionStore(requestLimit: 10)
    for transaction in transactions {
        await store.append(transaction)
    }
    return SystemInfoViewModel.traffic(
        quality: ConnectionQuality(recent: transactions), totals: await store.totals, downloads: downloads)
}

private func values(_ title: String, in sections: [SystemInfoSection]) -> [String: String] {
    let rows = sections.first { $0.title == title }?.rows ?? []
    return Dictionary(rows.map { ($0.title, $0.value) }) { first, _ in first }
}

@Test @MainActor func theSummarySaysOnlineOverWhatAndWhatNeedsASecondLook() {
    let summary = SystemInfoViewModel.summary(of: online)

    #expect(summary.title == "Online")
    #expect(summary.detail == "Cellular · 5G")
    #expect(summary.tone == .good)
    #expect(summary.badges == ["VPN", "Low Data Mode"])
}

@Test @MainActor func theSummaryShowsOfflineAndRequiresConnection() {
    #expect(SystemInfoViewModel.summary(of: SystemInfo(status: .offline)).title == "Offline")
    #expect(SystemInfoViewModel.summary(of: SystemInfo(status: .offline)).tone == .bad)
    #expect(SystemInfoViewModel.summary(of: SystemInfo(status: .requiresConnection)).tone == .warning)
    #expect(SystemInfoViewModel.summary(of: SystemInfo(status: .online)).badges.isEmpty)
}

@Test @MainActor func beforeTheNetworkIsKnownTheSummarySaysSo() {
    #expect(SystemInfoViewModel.summary(of: nil).tone == .unknown)
    #expect(SystemInfoViewModel.network(nil).isEmpty)
}

@Test @MainActor func connectionShowsEveryIncludedField() {
    let connection = values("Connection", in: SystemInfoViewModel.network(online))

    #expect(
        connection == [
            "Type": "Cellular", "Cellular generation": "5G", "Low Data Mode": "On", "Metered connection": "Yes",
            "VPN": "Connected", "Proxy": "Not detected",
        ])
}

@Test @MainActor func fieldsTheDeviceDoesntReportAreLeftOut() {
    let connection = values("Connection", in: SystemInfoViewModel.network(SystemInfo(status: .offline)))

    #expect(connection["Type"] == nil)
    #expect(connection["Cellular generation"] == nil)
    #expect(connection["VPN"] == "Not detected")
}

@Test @MainActor func nothingExcludedIsShown() async {
    let all =
        SystemInfoViewModel.network(online) + (await traffic([request()])) + SystemInfoViewModel.device(environment)
    let titles = all.flatMap(\.rows).map { $0.title.lowercased() }

    for excluded in ["signal", "carrier", "ssid", "wi-fi name"] {
        #expect(!titles.contains { $0.contains(excluded) })
    }
}

@Test @MainActor func addressesAreGroupedByInterfaceAndFamily() {
    let section = SystemInfoViewModel.network(online).first { $0.title == "IP addresses" }

    #expect(section?.rows.map(\.title) == ["Wi-Fi IPv4", "Wi-Fi IPv6", "Cellular IPv4", "Public IP"])
    #expect(section?.rows[1].value == "2001:db8::1\n2001:db8::2")
    #expect(section?.rows.last?.value == "203.0.113.7")
    #expect(section?.footer == nil)
}

@Test(arguments: [
    (SystemInfo.PublicIP.off, "Off"),
    (.loading, "Looking up…"),
    (.unavailable, "Unavailable"),
])
@MainActor func thePublicIPSaysWhyItHasNoAddress(state: SystemInfo.PublicIP, text: String) {
    let sections = SystemInfoViewModel.network(SystemInfo(status: .online, publicIP: state))

    #expect(values("IP addresses", in: sections)["Public IP"] == text)
}

@Test @MainActor func whenThePublicIPIsOffTheFooterSaysHowToTurnItOn() {
    let section = SystemInfoViewModel.network(SystemInfo(status: .online)).first { $0.title == "IP addresses" }

    #expect(section?.footer?.contains("isPublicIPLookupEnabled") == true)
}

@Test @MainActor func performanceIsInPlainWordsWithAnOverallRating() async {
    let all = await traffic([request(received: 250_000)])
    let performance = values("Performance", in: all)

    #expect(
        performance == [
            "Overall": "Good", "Server response time": "50 ms", "Connection setup": "200 ms",
            "Download speed": "125 KB/s",
        ])
    #expect(all.first { $0.title == "Performance" }?.footer?.contains("last request") == true)
}

@Test(arguments: [(0.29, "Good"), (0.3, "Fair"), (0.99, "Fair"), (1.0, "Slow")])
@MainActor func theRatingFollowsResponseTime(firstByte: TimeInterval, rating: String) async {
    let performance = values("Performance", in: await traffic([request(firstByte: firstByte)]))

    #expect(performance["Overall"] == rating)
}

@Test @MainActor func downloadSpeedIsLeftOutWhenResponsesAreTooSmallToMeasureIt() async {
    let performance = values("Performance", in: await traffic([request(received: 4_000)]))

    #expect(performance["Download speed"] == nil)
    #expect(performance["Server response time"] == "50 ms")
}

@Test @MainActor func performanceWithNoRequestsSaysSo() async {
    let performance = values("Performance", in: await traffic())

    #expect(performance == ["No requests yet": "—"])
}

@Test @MainActor func totalsAndTheirBreakdownsMatchTheRequests() async {
    let all = await traffic([request(), request()])

    #expect(values("This session", in: all) == ["Requests": "2", "Sent": "2 KB", "Received": "8 KB"])
    #expect(values("By host", in: all) == ["api.example.com": "↑ 2 KB  ↓ 8 KB"])
    #expect(values("By connection", in: all) == ["Cellular": "↑ 2 KB  ↓ 8 KB"])
}

@Test @MainActor func breakdownsAreHiddenUntilThereIsTraffic() async {
    let titles = await traffic().map(\.title)

    #expect(titles == ["Performance", "This session"])
}

@Test @MainActor func aDownloadShowsHowFarAlongItIsAtTheTop() async {
    let known = DownloadProgress(
        id: UUID(), url: URL(string: "https://example.com/files/app.zip"), startDate: Date(),
        bytesReceived: 1_000, expectedBytes: 4_000)
    let unknown = DownloadProgress(
        id: UUID(), url: URL(string: "https://cdn.example.com"), startDate: Date(), bytesReceived: 2_000)

    let all = await traffic(downloads: [known, unknown])

    #expect(all.first?.title == "Downloads in progress")
    #expect(values("Downloads in progress", in: all) == ["app.zip": "1 KB of 4 KB (25%)", "cdn.example.com": "2 KB"])
}

@Test @MainActor func theDevicePageShowsTheAppAndTheDevice() {
    let sections = SystemInfoViewModel.device(environment)

    #expect(
        values("App", in: sections) == [
            "Name": "Shop", "Version": "2.1 (45)", "Bundle ID": "com.example.shop", "Minimum iOS": "16.0",
        ])
    #expect(
        values("Device", in: sections) == [
            "Model": "iPhone", "Identifier": "iPhone17,3", "System": "iOS 26.4", "Memory": "8 GB",
            "Processor cores": "6", "Low Power Mode": "On", "Locale": "en_IN", "Time zone": "Asia/Kolkata",
        ])
}

@Test @MainActor func aSimulatorIsLabelledAndMissingAppFieldsAreLeftOut() {
    var simulated = environment
    simulated.isSimulator = true
    simulated.appName = nil
    simulated.version = nil
    simulated.build = nil

    let sections = SystemInfoViewModel.device(simulated)

    #expect(values("Device", in: sections)["Model"] == "iPhone (Simulator)")
    #expect(values("App", in: sections) == ["Bundle ID": "com.example.shop", "Minimum iOS": "16.0"])
}

@Test @MainActor func theRunningAppDescribesItself() {
    let current = AppEnvironment.current

    #expect(current.isSimulator)
    #expect(current.modelIdentifier?.isEmpty == false)
    #expect(current.memoryBytes > 0)
}

@Test @MainActor func exportsAreBuiltOffTheMainThread() async {
    #expect(Thread.isMainThread)

    let ranOnMain = await ExportActions.build { Thread.isMainThread }

    #expect(!ranOnMain)
}

@Test @MainActor func theInspectorShowsThroughput() {
    let model = LogInspectorViewModel(transaction: request())
    let size = model.sections(for: .metrics).first { $0.title == "Size" }

    #expect(size?.rows.first { $0.title == "Throughput" }?.value == "2 KB/s")
}
