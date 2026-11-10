import Foundation

/// One address on one of the device's network interfaces.
public struct InterfaceAddress: Sendable, Equatable {
    /// The interface's name, such as `en0` for Wi-Fi or `pdp_ip0` for cellular.
    public let interface: String

    /// The address, as text.
    public let address: String

    /// Whether the address is IPv6.
    public let isIPv6: Bool

    /// Creates an address.
    public init(interface: String, address: String, isIPv6: Bool) {
        self.interface = interface
        self.address = address
        self.isIPv6 = isIPv6
    }
}

/// Reads the device's own addresses with `getifaddrs`. Unsafe pointers stay inside this type.
enum NetworkInterfaces {
    /// Wi-Fi and cellular, which an app's traffic leaves through.
    private static let shownInterfaces: Set<String> = ["en0", "pdp_ip0"]

    /// Every address on every interface that's up.
    static func all() -> [InterfaceAddress] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var addresses: [InterfaceAddress] = []
        var next = first
        while let entry = next {
            next = entry.pointee.ifa_next
            guard entry.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                let socketAddress = entry.pointee.ifa_addr,
                let address = address(from: socketAddress)
            else { continue }
            addresses.append(
                InterfaceAddress(
                    interface: String(cString: entry.pointee.ifa_name),
                    address: address.text,
                    isIPv6: address.isIPv6
                )
            )
        }
        return addresses
    }

    /// Writes an IPv4 or IPv6 socket address as text, and returns `nil` for any other kind.
    static func address(from socketAddress: UnsafePointer<sockaddr>) -> (text: String, isIPv6: Bool)? {
        let family = Int32(socketAddress.pointee.sa_family)
        guard family == AF_INET || family == AF_INET6 else { return nil }
        let size = family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let result = getnameinfo(
            socketAddress, socklen_t(size), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
        let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard result == 0, let text = String(bytes: bytes, encoding: .utf8) else { return nil }
        return (text, family == AF_INET6)
    }

    /// The addresses worth showing: Wi-Fi's and cellular's, without link-local IPv6, which every
    /// interface has and which says nothing about the network.
    static func local(from all: [InterfaceAddress]) -> [InterfaceAddress] {
        all.filter { shownInterfaces.contains($0.interface) && !$0.address.lowercased().hasPrefix("fe80") }
    }
}
