import Foundation
import Testing
@testable import CerebroCore

extension CaptureTests {
    @Suite struct Bodies {
        @Test func readsAPostBodyFromItsStream() async throws {
            try await withCapture { harness in
                var request = URLRequest(url: harness.url("/post"))
                request.httpMethod = "POST"
                request.httpBody = Data("posted".utf8)

                _ = try await URLSession(configuration: .default).data(for: request)

                #expect(harness.server.requests.first?.body == Data("posted".utf8))
                #expect(harness.server.requests.first?.header("Content-Length") == "6")
                #expect(try await harness.transaction().request.body?.content == .complete(Data("posted".utf8)))
            }
        }

        @Test func readsAnUploadBodyFromItsStream() async throws {
            try await withCapture { harness in
                var request = URLRequest(url: harness.url("/upload"))
                request.httpMethod = "PUT"
                let payload = Data(repeating: 65, count: 5_000)

                _ = try await URLSession(configuration: .default).upload(for: request, from: payload)

                #expect(harness.server.requests.first?.body == payload)
                #expect(try await harness.transaction().request.body?.content == .complete(payload))
            }
        }

        @Test func uploadOverTheCapStaysIntactOnTheWireAndTruncatedInTheStore() async throws {
            let configuration = CerebroConfiguration(consoleLevel: .off, bodyLimit: 1_000)
            try await withCapture(configuration) { harness in
                var request = URLRequest(url: harness.url("/big-upload"))
                request.httpMethod = "PUT"
                let payload = Data((0..<300_000).map { UInt8($0 % 251) })

                _ = try await URLSession(configuration: .default).upload(for: request, from: payload)

                let received = try #require(harness.server.requests.first)
                #expect(received.body == payload)
                #expect(received.header("Content-Length") == "300000")
                let body = try #require(try await harness.transaction().request.body)
                #expect(body.content == .truncated(payload.prefix(1_000)))
                #expect(body.byteCount == 300_000)
            }
        }

        @Test func spooledUploadFileIsRemovedAfterwards() async throws {
            let configuration = CerebroConfiguration(consoleLevel: .off, bodyLimit: 1_000)
            try await withCapture(configuration) { harness in
                var request = URLRequest(url: harness.url("/spool"))
                request.httpMethod = "PUT"

                _ = try await URLSession(configuration: .default).upload(for: request, from: Data(count: 100_000))
                _ = try await harness.transaction()

                let files = try FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory())
                #expect(!files.contains { $0.hasPrefix("cerebro-upload-") })
            }
        }

        @Test func metricsFillTimingConnectionAndSize() async throws {
            try await withCapture { harness in
                _ = try await URLSession(configuration: .default).data(from: harness.url("/metrics"))

                let transaction = try await harness.transaction()
                let timing = try #require(transaction.timing)
                #expect(timing.total > 0)
                #expect(timing.firstByte != nil)
                #expect(transaction.connection?.remoteAddress == "127.0.0.1")
                #expect(transaction.connection?.httpVersion == "http/1.1")
                let size = try #require(transaction.size)
                #expect(size.bytesSent > 0)
                #expect(size.wireBodyBytes == 5)
                #expect(size.decodedBodyBytes == 5)
            }
        }

        @Test func gzipResponseShowsItsEncodingSizesAndRatio() async throws {
            let plain = Data(String(repeating: "cerebro ", count: 5_000).utf8)
            let compressed = try Fixtures.gzipWithTrailer(plain)
            let handler: CaptureHarness.Handler = { _ in
                LocalHTTPServer.Response(headers: ["Content-Encoding": "gzip"], body: compressed)
            }
            try await withCapture(handler: handler) { harness in
                let (data, _) = try await URLSession(configuration: .default).data(from: harness.url("/gzip"))

                #expect(data == plain)
                let transaction = try await harness.transaction()
                #expect(transaction.response?.contentEncoding == "gzip")
                #expect(transaction.response?.body?.content == .complete(plain))
                let size = try #require(transaction.size)
                #expect(size.wireBodyBytes == Int64(compressed.count))
                #expect(size.decodedBodyBytes == Int64(plain.count))
                #expect((size.compressionRatio ?? 0) > 10)
            }
        }

        @Test func responseOverTheCapReachesTheAppWholeAndTheStoreTruncated() async throws {
            let body = Data(repeating: 66, count: 5_000_000)
            let configuration = CerebroConfiguration(consoleLevel: .off, bodyLimit: 1_000)
            let handler: CaptureHarness.Handler = { _ in LocalHTTPServer.Response(body: body) }
            try await withCapture(configuration, handler: handler) { harness in
                let (data, _) = try await URLSession(configuration: .default).data(from: harness.url("/big"))

                #expect(data.count == body.count)
                let stored = try #require(try await harness.transaction().response?.body)
                #expect(stored.content == .truncated(body.prefix(1_000)))
                #expect(stored.byteCount == body.count)
            }
        }

        @Test func downloadTaskBodyIsNotStored() async throws {
            let body = Data(repeating: 67, count: 100_000)
            let handler: CaptureHarness.Handler = { _ in LocalHTTPServer.Response(body: body) }
            try await withCapture(handler: handler) { harness in
                let (file, _) = try await URLSession(configuration: .default).download(from: harness.url("/download"))

                #expect(try Data(contentsOf: file) == body)
                let stored = try #require(try await harness.transaction().response?.body)
                #expect(stored.content == .notStored)
                #expect(stored.byteCount == body.count)
            }
        }

        @Test func serverErrorIsARecordedResponseNotAFailure() async throws {
            let handler: CaptureHarness.Handler = { _ in LocalHTTPServer.Response(status: 500, reason: "Oops") }
            try await withCapture(handler: handler) { harness in
                _ = try await URLSession(configuration: .default).data(from: harness.url("/oops"))

                let transaction = try await harness.transaction()
                #expect(transaction.outcome == .serverError)
                #expect(transaction.failure == nil)
            }
        }
    }
}
