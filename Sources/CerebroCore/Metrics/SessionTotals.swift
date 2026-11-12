import Foundation

/// Bytes moved by every captured request this session. It's a running sum, so it stays true after
/// old requests leave the store.
public struct SessionTotals: Sendable, Equatable {
    /// The bytes for one host or one connection type.
    public struct Group: Sendable, Equatable {
        /// The host, or the connection type.
        public let name: String

        /// Header and body bytes sent.
        public let bytesSent: Int64

        /// Header and body bytes received on the wire.
        public let bytesReceived: Int64

        /// Creates a group.
        public init(name: String, bytesSent: Int64, bytesReceived: Int64) {
            self.name = name
            self.bytesSent = bytesSent
            self.bytesReceived = bytesReceived
        }
    }

    private struct Bytes: Equatable {
        var sent: Int64 = 0
        var received: Int64 = 0
    }

    /// Hosts past this many share one group, so a crawler-like app can't grow this without limit.
    static let hostLimit = 50
    static let otherHosts = "Other hosts"

    /// How many requests have been counted.
    public private(set) var requestCount = 0

    /// Header and body bytes sent.
    public private(set) var bytesSent: Int64 = 0

    /// Header and body bytes received on the wire.
    public private(set) var bytesReceived: Int64 = 0

    private var hosts: [String: Bytes] = [:]
    private var connectionTypes: [String: Bytes] = [:]

    /// Creates empty totals.
    public init() {}

    /// The totals for each host, largest first.
    public var byHost: [Group] {
        Self.groups(from: hosts)
    }

    /// The totals for cellular and for everything else, largest first.
    public var byConnectionType: [Group] {
        Self.groups(from: connectionTypes)
    }

    /// Counts a request. One with no metrics has no sizes, so it only adds to the count.
    mutating func add(_ transaction: HTTPTransaction) {
        requestCount += 1
        addBytes(of: transaction)
    }

    /// Adds a request's bytes without counting it again, for one that was counted before it had sizes.
    mutating func addBytes(of transaction: HTTPTransaction) {
        guard let size = transaction.size else { return }
        bytesSent += size.bytesSent
        bytesReceived += size.bytesReceived

        let host = transaction.request.url?.host ?? "No host"
        let hostKey = hosts[host] != nil || hosts.count < Self.hostLimit ? host : Self.otherHosts
        hosts[hostKey, default: Bytes()].sent += size.bytesSent
        hosts[hostKey, default: Bytes()].received += size.bytesReceived

        if let connection = transaction.connection {
            let type = connection.isCellular ? "Cellular" : "Wi-Fi or wired"
            connectionTypes[type, default: Bytes()].sent += size.bytesSent
            connectionTypes[type, default: Bytes()].received += size.bytesReceived
        }
    }

    private static func groups(from totals: [String: Bytes]) -> [Group] {
        totals
            .map { Group(name: $0.key, bytesSent: $0.value.sent, bytesReceived: $0.value.received) }
            .sorted {
                let (first, second) = ($0.bytesSent + $0.bytesReceived, $1.bytesSent + $1.bytesReceived)
                return first == second ? $0.name < $1.name : first > second
            }
    }
}
