import CoreTelephony

/// Names the cellular generation for a CoreTelephony radio access technology.
enum CellularGeneration {
    /// The generation of the service carrying data, and only while the connection is cellular. A phone
    /// on Wi-Fi still has a radio technology, and one with two SIMs has two.
    static func current(technologies: [String: String]?, dataService: String?, isCellular: Bool) -> String? {
        guard isCellular, let technologies else { return nil }
        let technology =
            dataService.flatMap { technologies[$0] } ?? (technologies.count == 1 ? technologies.values.first : nil)
        return technology.flatMap(name(forRadioAccessTechnology:))
    }

    static func name(forRadioAccessTechnology technology: String) -> String? {
        switch technology {
        case CTRadioAccessTechnologyNR, CTRadioAccessTechnologyNRNSA:
            return "5G"
        case CTRadioAccessTechnologyLTE:
            return "4G"
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA, CTRadioAccessTechnologyHSUPA,
            CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA,
            CTRadioAccessTechnologyCDMAEVDORevB, CTRadioAccessTechnologyeHRPD:
            return "3G"
        case CTRadioAccessTechnologyGPRS, CTRadioAccessTechnologyEdge, CTRadioAccessTechnologyCDMA1x:
            return "2G"
        default:
            return nil
        }
    }
}
