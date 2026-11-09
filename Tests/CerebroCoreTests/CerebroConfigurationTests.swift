import Testing
@testable import CerebroCore

@Test func defaultsMatchTheSpec() {
    let configuration = CerebroConfiguration()

    #expect(configuration.allowsDistributionBuilds == false)
    #expect(configuration.socketFrameLimit == 1_000)
    #expect(configuration.consoleLevel == .summary)
    #expect(configuration.requestLimit == 500)
    #expect(configuration.bodyLimit == 1_048_576)
    #expect(configuration.isShakeGestureEnabled)
    #expect(configuration.redaction.sensitiveHeaders.isEmpty)
    #expect(configuration.redaction.headers.isEmpty)
    #expect(configuration.redaction.jsonKeys.isEmpty)
    #expect(configuration.redaction.queryParameters.isEmpty)
    #expect(configuration.decoders.isEmpty)
}
