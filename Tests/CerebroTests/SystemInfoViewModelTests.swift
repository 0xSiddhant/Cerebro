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
        InterfaceAddress(interface: "pdp_ip0", address: "2001:db8::1", isIPv6: true),
    ],
    isVPNActive: true,
    isProxyActive: false,
    publicIP: .address("203.0.113.7")
)

@MainActor
private func sections(
    info: SystemInfo? = online,
    transactions: [HTTPTransaction] = [],
    downloads: [DownloadProgress] = []
) async -> [SystemInfoSection] {
    let store = TransactionStore(requestLimit: 10)
    for transaction in transactions {
        await store.append(transaction)
    }
    return SystemInfoViewModel.sections(
        info: info,
        quality: ConnectionQuality(recent: transactions),
        totals: await store.totals,
        downloads: downloads
    )
}

private func values(_ title: String, in sections: [SystemInfoSection]) -> [String: String] {
    let rows = sections.first { $0.title == title }?.rows ?? []
    return Dictionary(rows.map { ($0.title, $0.value) }) { first, _ in first }
}

private let request = HTTPTransaction(
    request: CapturedRequest(url: URL(string: "https://api.example.com/a"), method: "GET", startDate: Date()),
    timing: TransactionTiming(connect: 0.2, tls: 0.1, firstByte: 0.05, total: 2),
    connection: ConnectionDetails(isCellular: true),
    size: TransferSize(bytesSent: 1_000, bytesReceived: 4_000, wireBodyBytes: 0, decodedBodyBytes: 0)
)

@Test @MainActor func connectionShowsEveryIncludedField() async {
    let connection = await values("Connection", in: sections())

    #expect(
        connection == [
            "Status": "Online", "Type": "Cellular", "Cellular generation": "5G", "Low Data Mode": "On",
            "Expensive connection": "Yes", "VPN": "Connected", "Proxy": "Not detected",
        ])
}

@Test @MainActor func fieldsTheDeviceDoesntReportAreLeftOut() async {
    let connection = await values("Connection", in: sections(info: SystemInfo(status: .offline)))

    #expect(connection["Status"] == "Offline")
    #expect(connection["Type"] == nil)
    #expect(connection["Cellular generation"] == nil)
}

@Test @MainActor func nothingExcludedIsShown() async {
    let titles = await sections().flatMap(\.rows).map { $0.title.lowercased() }

    for excluded in ["signal", "carrier", "ssid", "wi-fi name"] {
        #expect(!titles.contains { $0.contains(excluded) })
    }
}

@Test @MainActor func addressesNameTheirInterfaceAndFamily() async {
    let addresses = await values("Addresses", in: sections())

    #expect(addresses["Wi-Fi IPv4"] == "192.168.1.20")
    #expect(addresses["Cellular IPv6"] == "2001:db8::1")
    #expect(addresses["Public IP"] == "203.0.113.7")
}

@Test(arguments: [
    (SystemInfo.PublicIP.off, "Off"),
    (.loading, "Looking up…"),
    (.unavailable, "Unavailable"),
])
@MainActor func thePublicIPSaysWhyItHasNoAddress(state: SystemInfo.PublicIP, text: String) async {
    let info = SystemInfo(status: .online, publicIP: state)

    let addresses = await values("Addresses", in: sections(info: info))
    #expect(addresses["Public IP"] == text)
}

@Test @MainActor func beforeTheNetworkIsKnownOnlyTheSessionShows() async {
    let titles = await sections(info: nil).map(\.title)

    #expect(titles == ["Connection quality", "Session totals"])
}

@Test @MainActor func qualityShowsItsAveragesAndWhatTheyCover() async {
    let all = await sections(transactions: [request])
    let quality = await values("Connection quality", in: all)

    #expect(quality == ["Latency": "50 ms", "Connect": "200 ms", "TLS": "100 ms", "Throughput": "2 KB/s"])
    #expect(all.first { $0.title == "Connection quality" }?.footer == "Averaged over the last request.")
}

@Test @MainActor func qualityWithNoRequestsSaysSo() async {
    let quality = await values("Connection quality", in: sections())
    #expect(quality == ["No requests yet": "—"])
}

@Test @MainActor func totalsAndTheirBreakdownsMatchTheRequests() async {
    let all = await sections(transactions: [request, request])

    #expect(values("Session totals", in: all) == ["Requests": "2", "Sent": "2 KB", "Received": "8 KB"])
    #expect(values("By host", in: all) == ["api.example.com": "↑ 2 KB  ↓ 8 KB"])
    #expect(values("By connection type", in: all) == ["Cellular": "↑ 2 KB  ↓ 8 KB"])
}

@Test @MainActor func breakdownsAreHiddenUntilThereIsTraffic() async {
    let titles = await sections().map(\.title)

    #expect(!titles.contains("By host"))
    #expect(!titles.contains("Active downloads"))
}

@Test @MainActor func aDownloadShowsHowFarAlongItIs() async {
    let known = DownloadProgress(
        id: UUID(), url: URL(string: "https://example.com/files/app.zip"), startDate: Date(),
        bytesReceived: 1_000, expectedBytes: 4_000)
    let unknown = DownloadProgress(
        id: UUID(), url: URL(string: "https://cdn.example.com"), startDate: Date(), bytesReceived: 2_000)

    let downloads = await values("Active downloads", in: sections(downloads: [known, unknown]))

    #expect(downloads == ["app.zip": "1 KB of 4 KB (25%)", "cdn.example.com": "2 KB"])
}

@Test @MainActor func exportsAreBuiltOffTheMainThread() async {
    #expect(Thread.isMainThread)

    let ranOnMain = await ExportActions.build { Thread.isMainThread }

    #expect(!ranOnMain)
}

@Test @MainActor func theInspectorShowsThroughput() {
    let model = LogInspectorViewModel(transaction: request)
    let size = model.sections(for: .metrics).first { $0.title == "Size" }

    #expect(size?.rows.first { $0.title == "Throughput" }?.value == "2 KB/s")
}
