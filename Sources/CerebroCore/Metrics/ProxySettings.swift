import CFNetwork
import Foundation

/// Reads whether a VPN or proxy is active from the system's proxy settings, which is the only public
/// place iOS says so.
enum ProxySettings {
    /// Interface names that only exist for a tunnel.
    private static let tunnelPrefixes = ["tap", "tun", "ppp", "ipsec", "utun"]
    private static let proxySwitches = ["HTTPEnable", "HTTPSEnable", "ProxyAutoConfigEnable"]

    static func current() -> [String: Any] {
        (CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any]) ?? [:]
    }

    /// A tunnel's interface is listed under the scoped settings while a VPN is connected.
    static func isVPNActive(in settings: [String: Any]) -> Bool {
        let scoped = settings["__SCOPED__"] as? [String: Any] ?? [:]
        return scoped.keys.contains { name in tunnelPrefixes.contains { name.hasPrefix($0) } }
    }

    static func isProxyActive(in settings: [String: Any]) -> Bool {
        proxySwitches.contains { (settings[$0] as? NSNumber)?.boolValue == true }
    }
}
