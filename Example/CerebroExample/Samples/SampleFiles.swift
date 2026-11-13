import UIKit

/// Writes a few files for the dashboard's Files tab to show, in `Documents/Samples`. Cerebro needs no code
/// for this: the tab reads whatever the app has on disk.
///
/// Each one opens differently. The JSON and the property list open as JSON, the property list in a tree,
/// the image in Quick Look, and the file with no extension as text.
enum SampleFiles {
    static func write() async throws -> String {
        try await Task.detached(priority: .utility) {
            let folder = try FileManager.default
                .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Samples", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let files = try [
                ("profile.json", profile()),
                ("settings.plist", settings()),
                ("avatar.png", avatar()),
                ("session-token", Data("eyJhbGciOiJIUzI1NiJ9.example.signature\n".utf8)),
            ]
            for (name, data) in files {
                try data.write(to: folder.appendingPathComponent(name), options: .atomic)
            }
            return "Wrote \(files.count) files to Documents/Samples"
        }
        .value
    }

    private static func profile() throws -> Data {
        let profile: [String: Any] = [
            "id": 42,
            "name": "Ada",
            "plan": ["tier": "pro", "renews": "2027-01-01"],
            "devices": ["iPhone", "iPad"],
        ]
        return try JSONSerialization.data(withJSONObject: profile, options: .sortedKeys)
    }

    /// Binary, like `UserDefaults` writes, with a date and data, which JSON can't hold as they are.
    private static func settings() throws -> Data {
        let settings: [String: Any] = [
            "theme": "dark",
            "launchCount": 7,
            "notificationsEnabled": true,
            "lastLaunch": Date(),
            "pushToken": Data([0xCA, 0xFE, 0xBA, 0xBE]),
        ]
        return try PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0)
    }

    private static func avatar() throws -> Data {
        let size = CGSize(width: 120, height: 120)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 30, y: 30, width: 60, height: 60))
        }
        guard let png = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        return png
    }
}
