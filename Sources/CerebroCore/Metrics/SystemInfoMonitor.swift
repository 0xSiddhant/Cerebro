import CoreTelephony
import Foundation
import Network

/// Watches the network the device is on. Nothing runs until something reads `updates()`, and after
/// that it only works when the network changes.
public actor SystemInfoMonitor {
    /// What an `NWPath` says, copied out so nothing else depends on Network types.
    struct Path: Sendable, Equatable {
        var status = SystemInfo.Status.offline
        var connectionType: SystemInfo.ConnectionType?
        var isLowDataMode = false
        var isExpensive = false

        init() {}

        init(_ path: NWPath) {
            switch path.status {
            case .satisfied: status = .online
            case .requiresConnection: status = .requiresConnection
            default: status = .offline
            }
            if path.usesInterfaceType(.wifi) {
                connectionType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                connectionType = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                connectionType = .wired
            } else if path.status == .satisfied {
                connectionType = .other
            }
            isLowDataMode = path.isConstrained
            isExpensive = path.isExpensive
        }
    }

    private let lookup: PublicIPLookup?
    /// Created with the path monitor, because it connects to a system service and most sessions never
    /// open the tab.
    private var telephony: CTTelephonyNetworkInfo?
    private var pathMonitor: NWPathMonitor?
    private var pathUpdates: Task<Void, Never>?
    private var path = Path()
    private var publicIP: SystemInfo.PublicIP
    private var runningLookup: Task<Void, Never>?
    private var observers = SnapshotObservers<SystemInfo>()

    /// `lookup` is `nil` unless the developer opted in, and then no external call is ever made.
    init(lookup: PublicIPLookup?) {
        self.lookup = lookup
        publicIP = lookup == nil ? .off : .loading
    }

    /// Delivers the current network now, then again whenever it changes.
    public func updates() -> AsyncStream<SystemInfo> {
        startIfNeeded()
        return observers.add(startingWith: snapshot()) { [weak self] id in
            Task { await self?.removeObserver(id) }
        }
    }

    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        pathUpdates?.cancel()
        pathUpdates = nil
        runningLookup?.cancel()
        runningLookup = nil
    }

    private func removeObserver(_ id: UUID) {
        observers.remove(id)
    }

    private func startIfNeeded() {
        guard pathMonitor == nil else { return }
        telephony = CTTelephonyNetworkInfo()
        let monitor = NWPathMonitor()
        // A stream keeps changes in order, which separate tasks wouldn't.
        let (paths, input) = AsyncStream.makeStream(of: Path.self, bufferingPolicy: .bufferingNewest(1))
        monitor.pathUpdateHandler = { input.yield(Path($0)) }
        monitor.start(queue: .global(qos: .utility))
        pathMonitor = monitor
        pathUpdates = Task { [weak self] in
            for await path in paths {
                await self?.pathChanged(to: path)
            }
        }
    }

    private func pathChanged(to newPath: Path) {
        path = newPath
        lookUpPublicIP()
        observers.publish(snapshot())
    }

    /// The public address can change with the network, so each change looks it up again.
    private func lookUpPublicIP() {
        guard let lookup else { return }
        runningLookup?.cancel()
        guard path.status == .online else {
            publicIP = .unavailable
            return
        }
        publicIP = .loading
        runningLookup = Task { [weak self] in
            let address = await lookup.address()
            guard !Task.isCancelled else { return }
            await self?.finishLookup(with: address)
        }
    }

    private func finishLookup(with address: String?) {
        publicIP = address.map(SystemInfo.PublicIP.address) ?? .unavailable
        observers.publish(snapshot())
    }

    private func snapshot() -> SystemInfo {
        let proxySettings = ProxySettings.current()
        let technology = telephony?.serviceCurrentRadioAccessTechnology?.values.first
        return SystemInfo(
            status: path.status,
            connectionType: path.connectionType,
            isLowDataMode: path.isLowDataMode,
            isExpensive: path.isExpensive,
            cellularGeneration: technology.flatMap(CellularGeneration.name(forRadioAccessTechnology:)),
            addresses: NetworkInterfaces.local(from: NetworkInterfaces.all()),
            isVPNActive: ProxySettings.isVPNActive(in: proxySettings),
            isProxyActive: ProxySettings.isProxyActive(in: proxySettings),
            publicIP: publicIP
        )
    }
}
