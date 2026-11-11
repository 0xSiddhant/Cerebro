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

    /// How often a network that isn't online is checked again. See `scheduleRecheck()`.
    static let recheckInterval: Duration = .seconds(2)

    private let lookup: PublicIPLookup?
    /// Created with the path monitor, because it connects to a system service and most sessions never
    /// open the tab.
    private var telephony: CTTelephonyNetworkInfo?
    private var pathMonitor: NWPathMonitor?
    private var pathUpdates: Task<Void, Never>?
    /// Which path monitor is current, so a late update from one that was replaced is ignored.
    private var monitorGeneration = 0
    private var recheck: Task<Void, Never>?
    /// `nil` until the system reports one, so nothing claims the device is offline before it's known.
    private var path: Path?
    private var publicIP: SystemInfo.PublicIP
    private var runningLookup: Task<Void, Never>?
    /// Which lookup is current, so one that was overtaken can't overwrite the newer result.
    private var lookupGeneration = 0
    private var observers = SnapshotObservers<SystemInfo>()

    /// `lookup` is `nil` unless the developer opted in, and then no external call is ever made.
    init(lookup: PublicIPLookup?) {
        self.lookup = lookup
        publicIP = lookup == nil ? .off : .loading
    }

    /// Delivers the network once it's known, then again whenever it changes.
    public func updates() -> AsyncStream<SystemInfo> {
        startIfNeeded()
        return observers.add(startingWith: snapshot()) { [weak self] id in
            Task { await self?.removeObserver(id) }
        }
    }

    var isRunning: Bool {
        pathMonitor != nil
    }

    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        pathUpdates?.cancel()
        pathUpdates = nil
        monitorGeneration += 1
        recheck?.cancel()
        recheck = nil
        runningLookup?.cancel()
        runningLookup = nil
        lookupGeneration += 1
        path = nil
        telephony = nil
        publicIP = lookup == nil ? .off : .loading
    }

    /// Stops when the last reader leaves, so nothing runs, and no lookup leaves the device, while the
    /// dashboard is closed.
    private func removeObserver(_ id: UUID) {
        observers.remove(id)
        if observers.isEmpty {
            stop()
        }
    }

    private func startIfNeeded() {
        guard pathMonitor == nil else { return }
        telephony = CTTelephonyNetworkInfo()
        startPathMonitor()
    }

    /// Replaces any path monitor with a new one, which reports the network as it is now.
    private func startPathMonitor() {
        pathMonitor?.cancel()
        pathUpdates?.cancel()
        monitorGeneration += 1
        let monitor = NWPathMonitor()
        // A stream keeps changes in order, which separate tasks wouldn't.
        let (paths, input) = AsyncStream.makeStream(of: Path.self, bufferingPolicy: .bufferingNewest(1))
        monitor.pathUpdateHandler = { input.yield(Path($0)) }
        monitor.start(queue: .global(qos: .utility))
        pathMonitor = monitor
        pathUpdates = Task { [weak self, generation = monitorGeneration] in
            for await path in paths {
                await self?.pathChanged(to: path, generation: generation)
            }
        }
    }

    private func pathChanged(to newPath: Path, generation: Int) {
        guard generation == monitorGeneration else { return }
        show(newPath)
    }

    func show(_ newPath: Path) {
        guard isRunning else { return }
        path = newPath
        lookUpPublicIP(isOnline: newPath.status == .online)
        publishSnapshot()
        scheduleRecheck()
    }

    /// A path monitor can miss the network coming back, which the simulator does when the Mac
    /// reconnects, while a new one always starts from the real state. So while the network isn't
    /// online and someone is reading, a new monitor takes over every few seconds.
    private func scheduleRecheck() {
        recheck?.cancel()
        recheck = nil
        guard path?.status != .online else { return }
        recheck = Task { [weak self] in
            try? await Task.sleep(for: Self.recheckInterval)
            guard !Task.isCancelled else { return }
            await self?.recheckPath()
        }
    }

    private func recheckPath() {
        guard isRunning, path?.status != .online else { return }
        startPathMonitor()
        // In case the new monitor reports nothing, so the checks don't stop.
        scheduleRecheck()
    }

    private func publishSnapshot() {
        if let snapshot = snapshot() {
            observers.publish(snapshot)
        }
    }

    /// The public address can change with the network, so each change looks it up again.
    private func lookUpPublicIP(isOnline: Bool) {
        guard let lookup else { return }
        runningLookup?.cancel()
        lookupGeneration += 1
        guard isOnline else {
            publicIP = .unavailable
            return
        }
        publicIP = .loading
        runningLookup = Task { [weak self, generation = lookupGeneration] in
            let address = await lookup.address()
            await self?.finishLookup(with: address, generation: generation)
        }
    }

    /// Checked here, on the actor, because a lookup can be overtaken while it waits to get in.
    func finishLookup(with address: String?, generation: Int) {
        guard generation == lookupGeneration else { return }
        publicIP = address.map(SystemInfo.PublicIP.address) ?? .unavailable
        publishSnapshot()
    }

    private func snapshot() -> SystemInfo? {
        guard let path else { return nil }
        let proxySettings = ProxySettings.current()
        let generation = CellularGeneration.current(
            technologies: telephony?.serviceCurrentRadioAccessTechnology,
            dataService: telephony?.dataServiceIdentifier,
            isCellular: path.connectionType == .cellular
        )
        return SystemInfo(
            status: path.status,
            connectionType: path.connectionType,
            isLowDataMode: path.isLowDataMode,
            isExpensive: path.isExpensive,
            cellularGeneration: generation,
            addresses: NetworkInterfaces.local(from: NetworkInterfaces.all()),
            isVPNActive: ProxySettings.isVPNActive(in: proxySettings),
            isProxyActive: ProxySettings.isProxyActive(in: proxySettings),
            publicIP: publicIP
        )
    }
}
