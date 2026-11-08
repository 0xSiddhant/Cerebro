import Foundation

/// Turns stored bytes into text, on demand. Only ever runs when a body is opened or logged in full.
public enum BodyFormatter {
    private static let hexDigits = Array("0123456789abcdef".utf8)

    /// Formats JSON with indentation, or returns `nil` if the bytes aren't JSON.
    public static func prettyJSON(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
            )
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    /// Reads bytes as UTF-8 text, falling back to hex.
    public static func text(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? hex(data)
    }

    private static func hex(_ data: Data) -> String {
        var digits = [UInt8]()
        digits.reserveCapacity(data.count * 2)
        for byte in data {
            digits.append(hexDigits[Int(byte >> 4)])
            digits.append(hexDigits[Int(byte & 0x0F)])
        }
        return String(bytes: digits, encoding: .ascii) ?? ""
    }
}
