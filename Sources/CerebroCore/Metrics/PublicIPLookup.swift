import Foundation
import Network

/// Asks an external service for the device's public IP. This is the only call Cerebro makes off the
/// device, it only exists when the developer opted in, and it never appears in the logs.
struct PublicIPLookup: Sendable {
    /// Returns the caller's address as plain text.
    static let serviceAddress = "https://api.ipify.org"

    private let url: URL
    private let session: URLSession

    /// The lookup against the real service, or `nil` unless the developer opted in.
    static func ifEnabled(_ isEnabled: Bool) -> Self? {
        isEnabled ? URL(string: serviceAddress).map(Self.init) : nil
    }

    init(url: URL) {
        self.url = url
        let configuration = URLSessionConfiguration.ephemeral
        // No protocol classes, so Cerebro's own capture never sees this request.
        configuration.protocolClasses = []
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
    }

    /// The address, or `nil` if the lookup failed or the answer isn't an IP address, as behind a
    /// captive portal.
    func address() async -> String? {
        guard let (data, response) = try? await session.data(from: url),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let text = String(data: data.prefix(64), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            IPv4Address(text) != nil || IPv6Address(text) != nil
        else { return nil }
        return text
    }
}
