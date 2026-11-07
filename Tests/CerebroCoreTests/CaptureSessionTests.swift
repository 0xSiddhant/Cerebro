import Foundation
import Testing
@testable import CerebroCore

extension CaptureTests {
    @Suite struct Sessions {
        @Test func capturesASessionBuiltFromTheDefaultGetter() async throws {
            try await withCapture { harness in
                let session = URLSession(configuration: .default)
                let (data, _) = try await session.data(from: harness.url("/default"))

                #expect(data == Data("hello".utf8))
                let transaction = try await harness.transaction()
                #expect(transaction.request.url == harness.url("/default"))
                #expect(transaction.request.method == "GET")
                #expect(transaction.response?.statusCode == 200)
                #expect(transaction.response?.body?.content == .complete(Data("hello".utf8)))
                #expect(transaction.outcome == .success)
            }
        }

        @Test func capturesASessionBuiltFromTheEphemeralGetter() async throws {
            try await withCapture { harness in
                let session = URLSession(configuration: .ephemeral)
                _ = try await session.data(from: harness.url("/ephemeral"))

                #expect(try await harness.transaction().request.url == harness.url("/ephemeral"))
            }
        }

        @Test func capturesTheSharedSessionAndStopEndsThatCapture() async throws {
            try await withCapture { harness in
                _ = try await URLSession.shared.data(from: harness.url("/shared"))
                #expect(try await harness.transaction().request.url == harness.url("/shared"))

                harness.runtime.stop()
                _ = try await URLSession.shared.data(from: harness.url("/after-stop"))

                #expect(harness.server.requests.count == 2)
                #expect(await harness.runtime.store.transactions.count == 1)
            }
        }

        @Test func sessionMadeBeforeStartKeepsWorkingAfterStop() async throws {
            try await withCapture { harness in
                let session = URLSession(configuration: .default)
                harness.runtime.stop()

                let (data, _) = try await session.data(from: harness.url("/stopped"))

                #expect(data == Data("hello".utf8))
                #expect(await harness.runtime.store.transactions.isEmpty)
            }
        }

        @Test func stopRestoresTheGetters() throws {
            let runtime = CaptureRuntime(unchecked: CerebroConfiguration(consoleLevel: .off))
            runtime.start()
            #expect(URLSessionConfiguration.default.protocolClasses?.first == CustomURLProtocol.self)
            #expect(URLSessionConfiguration.ephemeral.protocolClasses?.first == EphemeralURLProtocol.self)

            runtime.stop()

            #expect(URLSessionConfiguration.default.protocolClasses?.first != CustomURLProtocol.self)
            #expect(URLSessionConfiguration.ephemeral.protocolClasses?.first != EphemeralURLProtocol.self)
        }

        @Test func closedGateMeansNoRuntimeAndNoSwizzling() {
            let closed = ReleaseGate.Environment(isSimulator: false, provisioningProfile: nil)

            let runtime = CaptureRuntime(configuration: CerebroConfiguration(), environment: closed)

            #expect(runtime == nil)
            #expect(URLSessionConfiguration.default.protocolClasses?.first != CustomURLProtocol.self)
        }

        @Test func optInOpensAClosedGate() {
            let closed = ReleaseGate.Environment(isSimulator: false, provisioningProfile: nil)
            let configuration = CerebroConfiguration(allowsDistributionBuilds: true, consoleLevel: .off)

            #expect(CaptureRuntime(configuration: configuration, environment: closed) != nil)
        }

        @Test func sessionHeadersStillReachTheServer() async throws {
            try await withCapture { harness in
                let configuration = URLSessionConfiguration.default
                configuration.httpAdditionalHeaders = ["X-Session-Token": "from-config"]

                _ = try await URLSession(configuration: configuration).data(from: harness.url("/headers"))

                #expect(harness.server.requests.first?.header("X-Session-Token") == "from-config")
            }
        }

        @Test func appProtocolClassesReplacingOursTurnCaptureOffForThatSession() async throws {
            try await withCapture { harness in
                let configuration = URLSessionConfiguration.default
                configuration.protocolClasses = []

                _ = try await URLSession(configuration: configuration).data(from: harness.url("/own"))

                #expect(harness.server.requests.count == 1)
                #expect(await harness.runtime.store.transactions.isEmpty)
            }
        }
    }
}
