import Foundation

/// The network the device is on, from what iOS exposes publicly.
public struct SystemInfo: Sendable, Equatable {
    /// Whether the device can reach the network.
    public enum Status: Sendable, Equatable {
        /// A usable connection.
        case online

        /// No connection.
        case offline

        /// A connection that needs something first, such as a VPN to connect.
        case requiresConnection
    }

    /// What the connection runs over.
    public enum ConnectionType: Sendable, Equatable {
        /// Wi-Fi.
        case wifi

        /// Cellular.
        case cellular

        /// Wired Ethernet.
        case wired

        /// Anything else, such as a tunnel.
        case other
    }

    /// The device's address as the internet sees it.
    public enum PublicIP: Sendable, Equatable {
        /// The lookup is off, which is the default.
        case off

        /// The lookup is running.
        case loading

        /// The address.
        case address(String)

        /// The lookup failed.
        case unavailable
    }

    /// Whether the device can reach the network.
    public var status: Status

    /// What the connection runs over, if there is one.
    public var connectionType: ConnectionType?

    /// Whether Low Data Mode applies to the connection.
    public var isLowDataMode: Bool

    /// Whether the connection is expensive, such as cellular or a personal hotspot.
    public var isExpensive: Bool

    /// The cellular generation, such as `5G`, if the device reports one.
    public var cellularGeneration: String?

    /// The device's own Wi-Fi and cellular addresses.
    public var addresses: [InterfaceAddress]

    /// Whether a VPN is connected.
    public var isVPNActive: Bool

    /// Whether a system proxy is on.
    public var isProxyActive: Bool

    /// The device's public address.
    public var publicIP: PublicIP

    /// Creates a description of the network.
    public init(
        status: Status,
        connectionType: ConnectionType? = nil,
        isLowDataMode: Bool = false,
        isExpensive: Bool = false,
        cellularGeneration: String? = nil,
        addresses: [InterfaceAddress] = [],
        isVPNActive: Bool = false,
        isProxyActive: Bool = false,
        publicIP: PublicIP = .off
    ) {
        self.status = status
        self.connectionType = connectionType
        self.isLowDataMode = isLowDataMode
        self.isExpensive = isExpensive
        self.cellularGeneration = cellularGeneration
        self.addresses = addresses
        self.isVPNActive = isVPNActive
        self.isProxyActive = isProxyActive
        self.publicIP = publicIP
    }
}
