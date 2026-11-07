import Foundation
import Testing
@testable import CerebroCore

private func profile(getTaskAllow: Bool) -> Data {
    let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Entitlements</key><dict><key>get-task-allow</key><\(getTaskAllow)/></dict>
        </dict></plist>
        """
    // A real profile wraps the plist in binary signing data, on both sides.
    return Data([0x30, 0x82, 0xFF, 0x00]) + Data(plist.utf8) + Data([0xA0, 0x82, 0x00, 0xFF])
}

private func environment(isSimulator: Bool = false, profile: Data? = nil) -> ReleaseGate.Environment {
    ReleaseGate.Environment(isSimulator: isSimulator, provisioningProfile: profile)
}

@Test func openOnASimulator() {
    #expect(ReleaseGate.isOpen(allowsDistributionBuilds: false, environment: environment(isSimulator: true)))
}

@Test func openWhenDevelopmentSigned() {
    let development = environment(profile: profile(getTaskAllow: true))

    #expect(ReleaseGate.isOpen(allowsDistributionBuilds: false, environment: development))
}

@Test func closedWhenAdHocSigned() {
    let adHoc = environment(profile: profile(getTaskAllow: false))

    #expect(!ReleaseGate.isOpen(allowsDistributionBuilds: false, environment: adHoc))
}

@Test func closedWithNoProfileAsInAppStoreAndTestFlightBuilds() {
    #expect(!ReleaseGate.isOpen(allowsDistributionBuilds: false, environment: environment()))
}

@Test func closedWhenTheProfileCantBeRead() {
    let garbage = environment(profile: Data([0x00, 0x01, 0x02]))

    #expect(!ReleaseGate.isOpen(allowsDistributionBuilds: false, environment: garbage))
}

@Test func optInOpensADistributionBuild() {
    #expect(ReleaseGate.isOpen(allowsDistributionBuilds: true, environment: environment()))
}
