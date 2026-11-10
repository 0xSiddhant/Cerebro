import Foundation

/// How the connection has been performing, averaged over the most recent requests. iOS has no
/// signal-strength API, so this stands in for it.
public struct ConnectionQuality: Sendable, Equatable {
    /// How many recent requests the averages cover.
    public static let sampleLimit = 20

    /// The average time to the first response byte, in seconds.
    public let latency: TimeInterval?

    /// The average time to connect, in seconds, over requests that opened a connection.
    public let connect: TimeInterval?

    /// The average TLS handshake, in seconds, over requests that made one.
    public let tls: TimeInterval?

    /// The average throughput, in bytes per second.
    public let throughput: Double?

    /// How many requests the averages cover.
    public let sampleCount: Int

    /// Averages the newest requests that have timing. `transactions` is oldest first.
    public init(recent transactions: [HTTPTransaction]) {
        let samples = transactions.filter { $0.timing != nil }.suffix(Self.sampleLimit)
        sampleCount = samples.count
        latency = Self.average(samples.compactMap { $0.timing?.firstByte })
        connect = Self.average(samples.compactMap { $0.timing?.connect })
        tls = Self.average(samples.compactMap { $0.timing?.tls })
        throughput = Self.average(samples.compactMap(\.throughput))
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

extension HTTPTransaction {
    /// Bytes received on the wire per second, over the whole request.
    public var throughput: Double? {
        guard let total = timing?.total, total > 0, let received = size?.bytesReceived, received > 0 else {
            return nil
        }
        return Double(received) / total
    }
}
