import UIKit

/// The app Cerebro is running in and the device it's on, read once when the tab opens.
struct AppEnvironment: Equatable {
    var appName: String?
    var version: String?
    var build: String?
    var bundleIdentifier: String?
    var minimumSystemVersion: String?

    var model: String
    var modelIdentifier: String?
    var system: String
    var isSimulator: Bool
    var memoryBytes: UInt64
    var processorCount: Int
    var isLowPowerModeOn: Bool
    var locale: String
    var timeZone: String

    @MainActor static var current: Self {
        let info = Bundle.main.infoDictionary ?? [:]
        let device = UIDevice.current
        let process = ProcessInfo.processInfo
        let simulatedModel = process.environment["SIMULATOR_MODEL_IDENTIFIER"]
        return Self(
            appName: (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String,
            version: info["CFBundleShortVersionString"] as? String,
            build: info["CFBundleVersion"] as? String,
            bundleIdentifier: Bundle.main.bundleIdentifier,
            minimumSystemVersion: info["MinimumOSVersion"] as? String,
            model: device.model,
            modelIdentifier: simulatedModel ?? hardwareIdentifier(),
            system: "\(device.systemName) \(device.systemVersion)",
            isSimulator: simulatedModel != nil,
            memoryBytes: process.physicalMemory,
            processorCount: process.processorCount,
            isLowPowerModeOn: process.isLowPowerModeEnabled,
            locale: Locale.current.identifier,
            timeZone: TimeZone.current.identifier
        )
    }

    /// The hardware's own name, such as `iPhone17,3`, which is what crash reports and support use.
    private static func hardwareIdentifier() -> String? {
        var system = utsname()
        guard uname(&system) == 0 else { return nil }
        return withUnsafeBytes(of: &system.machine) { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) }
    }
}
