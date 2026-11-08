import Foundation

/// Decides whether capture may run in this build, from how the app is signed. It's a runtime check
/// because a prebuilt XCFramework can't see the app's build configuration.
enum ReleaseGate {
    /// What the gate looks at. Tests pass their own values.
    struct Environment {
        let isSimulator: Bool
        let provisioningProfile: Data?

        static var current: Self {
            #if targetEnvironment(simulator)
            Self(isSimulator: true, provisioningProfile: nil)
            #else
            let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
            return Self(isSimulator: false, provisioningProfile: url.flatMap { try? Data(contentsOf: $0) })
            #endif
        }
    }

    static func isOpen(allowsDistributionBuilds: Bool, environment: Environment = .current) -> Bool {
        allowsDistributionBuilds || environment.isSimulator
            || isDevelopmentSigned(profile: environment.provisioningProfile)
    }

    /// App Store and TestFlight builds have no profile, and Ad Hoc profiles don't set `get-task-allow`.
    static func isDevelopmentSigned(profile: Data?) -> Bool {
        guard let plist = profile.flatMap(propertyList),
            let entitlements = plist["Entitlements"] as? [String: Any]
        else { return false }
        return entitlements["get-task-allow"] as? Bool ?? false
    }

    /// A profile is a signed wrapper around an XML property list, which can be read straight out of it.
    private static func propertyList(in profile: Data) -> [String: Any]? {
        guard let start = profile.range(of: Data("<?xml".utf8)),
            let end = profile.range(of: Data("</plist>".utf8), in: start.lowerBound..<profile.endIndex)
        else { return nil }
        let xml = profile[start.lowerBound..<end.upperBound]
        return (try? PropertyListSerialization.propertyList(from: xml, format: nil)) as? [String: Any]
    }
}
