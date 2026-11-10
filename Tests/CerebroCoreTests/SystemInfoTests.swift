import CoreTelephony
import Foundation
import Testing
@testable import CerebroCore

private func transaction(
    host: String = "example.com",
    sent: Int64 = 100,
    received: Int64 = 1_000,
    timing: TransactionTiming? = TransactionTiming(total: 1),
    isCellular: Bool = false,
    hasSize: Bool = true
) -> HTTPTransaction {
    HTTPTransaction(
        request: CapturedRequest(
            url: URL(string: "https://\(host)/"), method: "GET", startDate: Date(timeIntervalSince1970: 0)),
        timing: timing,
        connection: ConnectionDetails(isCellular: isCellular),
        size: hasSize
            ? TransferSize(bytesSent: sent, bytesReceived: received, wireBodyBytes: 0, decodedBodyBytes: 0) : nil
    )
}

@Test func anIPv4SocketAddressIsWrittenAsText() throws {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    #expect(inet_pton(AF_INET, "192.168.1.20", &address.sin_addr) == 1)

    let parsed = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { NetworkInterfaces.address(from: $0) }
    }

    #expect(parsed?.text == "192.168.1.20")
    #expect(parsed?.isIPv6 == false)
}

@Test func anIPv6SocketAddressIsWrittenAsText() throws {
    var address = sockaddr_in6()
    address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
    address.sin6_family = sa_family_t(AF_INET6)
    #expect(inet_pton(AF_INET6, "2001:db8::1", &address.sin6_addr) == 1)

    let parsed = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { NetworkInterfaces.address(from: $0) }
    }

    #expect(parsed?.text == "2001:db8::1")
    #expect(parsed?.isIPv6 == true)
}

@Test func otherAddressFamiliesAreSkipped() {
    var address = sockaddr()
    address.sa_family = sa_family_t(AF_LINK)

    #expect(NetworkInterfaces.address(from: &address) == nil)
}

@Test func theDeviceReportsItsLoopbackAddress() {
    #expect(NetworkInterfaces.all().contains { $0.interface == "lo0" && $0.address == "127.0.0.1" })
}

@Test func onlyWiFiAndCellularAddressesAreShownWithoutLinkLocal() {
    let all = [
        InterfaceAddress(interface: "lo0", address: "127.0.0.1", isIPv6: false),
        InterfaceAddress(interface: "en0", address: "192.168.1.20", isIPv6: false),
        InterfaceAddress(interface: "en0", address: "fe80::1%en0", isIPv6: true),
        InterfaceAddress(interface: "en0", address: "2001:db8::1", isIPv6: true),
        InterfaceAddress(interface: "pdp_ip0", address: "10.0.0.5", isIPv6: false),
        InterfaceAddress(interface: "utun2", address: "10.8.0.2", isIPv6: false),
    ]

    #expect(NetworkInterfaces.local(from: all).map(\.address) == ["192.168.1.20", "2001:db8::1", "10.0.0.5"])
}

@Test(arguments: ["utun3", "ipsec0", "ppp0", "tun0", "tap0"])
func aTunnelInTheScopedSettingsMeansAVPN(interface: String) {
    #expect(ProxySettings.isVPNActive(in: ["__SCOPED__": ["en0": [:], interface: [:]]]))
}

@Test func noTunnelMeansNoVPN() {
    #expect(!ProxySettings.isVPNActive(in: ["__SCOPED__": ["en0": [:], "pdp_ip0": [:]]]))
    #expect(!ProxySettings.isVPNActive(in: [:]))
}

@Test(arguments: ["HTTPEnable", "HTTPSEnable", "ProxyAutoConfigEnable"])
func anEnabledProxySwitchMeansAProxy(key: String) {
    #expect(ProxySettings.isProxyActive(in: [key: 1]))
    #expect(!ProxySettings.isProxyActive(in: [key: 0]))
}

@Test func noProxySettingsMeanNoProxy() {
    #expect(!ProxySettings.isProxyActive(in: ["HTTPProxy": "10.0.0.1"]))
}

@Test func radioTechnologiesMapToGenerations() {
    #expect(CellularGeneration.name(forRadioAccessTechnology: CTRadioAccessTechnologyNR) == "5G")
    #expect(CellularGeneration.name(forRadioAccessTechnology: CTRadioAccessTechnologyNRNSA) == "5G")
    #expect(CellularGeneration.name(forRadioAccessTechnology: CTRadioAccessTechnologyLTE) == "4G")
    #expect(CellularGeneration.name(forRadioAccessTechnology: CTRadioAccessTechnologyHSDPA) == "3G")
    #expect(CellularGeneration.name(forRadioAccessTechnology: CTRadioAccessTechnologyEdge) == "2G")
    #expect(CellularGeneration.name(forRadioAccessTechnology: "SomethingNew") == nil)
}

@Test func throughputIsBytesReceivedPerSecond() {
    #expect(transaction(received: 3_000, timing: TransactionTiming(total: 2)).throughput == 1_500)
    #expect(transaction(timing: nil).throughput == nil)
    #expect(transaction(received: 0).throughput == nil)
    #expect(transaction(timing: TransactionTiming(total: 0)).throughput == nil)
}

@Test func qualityAveragesEachStageOverTheRequestsThatHadIt() {
    let quality = ConnectionQuality(recent: [
        transaction(received: 1_000, timing: TransactionTiming(connect: 0.2, tls: 0.1, firstByte: 0.1, total: 1)),
        transaction(received: 3_000, timing: TransactionTiming(firstByte: 0.3, total: 1)),
        transaction(timing: nil),
    ])

    #expect(quality.sampleCount == 2)
    #expect(quality.latency == 0.2)
    #expect(quality.connect == 0.2)
    #expect(quality.tls == 0.1)
    #expect(quality.throughput == 2_000)
}

@Test func qualityOnlyCoversTheNewestRequests() {
    let old = transaction(timing: TransactionTiming(firstByte: 9, total: 10))
    let recent = (0..<ConnectionQuality.sampleLimit).map { _ in
        transaction(timing: TransactionTiming(firstByte: 0.5, total: 1))
    }

    let quality = ConnectionQuality(recent: [old] + recent)

    #expect(quality.sampleCount == ConnectionQuality.sampleLimit)
    #expect(quality.latency == 0.5)
}

@Test func qualityWithNoRequestsHasNoAverages() {
    let quality = ConnectionQuality(recent: [])

    #expect(quality.sampleCount == 0)
    #expect(quality.latency == nil)
    #expect(quality.throughput == nil)
}

@Test func totalsBreakDownByHostAndConnectionType() {
    var totals = SessionTotals()

    totals.add(transaction(host: "a.com", sent: 10, received: 100))
    totals.add(transaction(host: "a.com", sent: 5, received: 50))
    totals.add(transaction(host: "b.com", sent: 1, received: 1_000, isCellular: true))

    #expect(totals.requestCount == 3)
    #expect(totals.bytesSent == 16)
    #expect(totals.bytesReceived == 1_150)
    #expect(
        totals.byHost == [
            SessionTotals.Group(name: "b.com", bytesSent: 1, bytesReceived: 1_000),
            SessionTotals.Group(name: "a.com", bytesSent: 15, bytesReceived: 150),
        ])
    #expect(
        totals.byConnectionType == [
            SessionTotals.Group(name: "Cellular", bytesSent: 1, bytesReceived: 1_000),
            SessionTotals.Group(name: "Wi-Fi or wired", bytesSent: 15, bytesReceived: 150),
        ])
}

@Test func aRequestWithNoMetricsOnlyAddsToTheCount() {
    var totals = SessionTotals()

    totals.add(transaction(hasSize: false))

    #expect(totals.requestCount == 1)
    #expect(totals.bytesReceived == 0)
    #expect(totals.byHost.isEmpty)
}

@Test func hostsPastTheLimitShareOneGroup() {
    var totals = SessionTotals()

    for index in 0..<(SessionTotals.hostLimit + 5) {
        totals.add(transaction(host: "host\(index).com", sent: 1, received: 1))
    }
    totals.add(transaction(host: "host0.com", sent: 1, received: 1))

    #expect(totals.byHost.count == SessionTotals.hostLimit + 1)
    #expect(totals.byHost.first == SessionTotals.Group(name: SessionTotals.otherHosts, bytesSent: 5, bytesReceived: 5))
    #expect(totals.byHost.contains(SessionTotals.Group(name: "host0.com", bytesSent: 2, bytesReceived: 2)))
}

@Test func totalsOutliveTheRequestsTheStoreDrops() async {
    let store = TransactionStore(requestLimit: 1)

    await store.append(transaction(sent: 10, received: 100))
    await store.append(transaction(sent: 10, received: 100))

    #expect(await store.transactions.count == 1)
    #expect(await store.totals.requestCount == 2)
    #expect(await store.totals.bytesReceived == 200)
}

@Test func aMonitorWithNoLookupReportsThePublicIPAsOff() async throws {
    let monitor = SystemInfoMonitor(lookup: nil)
    defer { Task { await monitor.stop() } }

    var updates = await monitor.updates().makeAsyncIterator()
    let info = try #require(await updates.next())

    #expect(info.publicIP == .off)
}
