import Foundation
import Testing
@testable import CerebroCore

private let start = Date(timeIntervalSince1970: 0)
private let file = URL(string: "https://example.com/file.zip")

@Test func aDownloadIsTrackedFromStartToFinish() async {
    let store = DownloadProgressStore()
    let id = UUID()

    await store.apply(.started(id: id, url: file, date: start))
    await store.apply(.received(id: id, bytes: 250, expectedBytes: 1_000, mimeType: "application/zip"))

    let download = await store.active.first
    #expect(download?.url == file)
    #expect(download?.bytesReceived == 250)
    #expect(download?.fractionCompleted == 0.25)
    #expect(download?.mimeType == "application/zip")

    await store.apply(.finished(id: id))

    #expect(await store.active.isEmpty)
}

@Test func progressWithNoAnnouncedSizeHasNoFraction() async {
    let store = DownloadProgressStore()
    let id = UUID()

    await store.apply(.started(id: id, url: file, date: start))
    await store.apply(.received(id: id, bytes: 250, expectedBytes: nil, mimeType: nil))

    #expect(await store.active.first?.fractionCompleted == nil)
}

@Test func progressForAnUnknownDownloadIsIgnored() async {
    let store = DownloadProgressStore()

    await store.apply(.received(id: UUID(), bytes: 1, expectedBytes: nil, mimeType: nil))
    await store.apply(.finished(id: UUID()))

    #expect(await store.active.isEmpty)
}

@Test func downloadsPastTheLimitArentTracked() async {
    let store = DownloadProgressStore()

    for _ in 0..<(DownloadProgressStore.limit + 10) {
        await store.apply(.started(id: UUID(), url: file, date: start))
    }

    #expect(await store.active.count == DownloadProgressStore.limit)
}

@Test func downloadsStayInTheOrderTheyStarted() async {
    let store = DownloadProgressStore()
    let (first, second) = (UUID(), UUID())

    await store.apply(.started(id: first, url: file, date: start))
    await store.apply(.started(id: second, url: file, date: start))
    await store.apply(.received(id: first, bytes: 5, expectedBytes: nil, mimeType: nil))

    #expect(await store.active.map(\.id) == [first, second])
}

@Test func aBurstOfProgressArrivesAsOneBatch() async throws {
    let store = DownloadProgressStore(updateInterval: .milliseconds(200))
    let id = UUID()
    var updates = await store.updates().makeAsyncIterator()
    #expect(await updates.next()?.isEmpty == true)

    await store.apply(.started(id: id, url: file, date: start))
    for bytes in 1...50 {
        await store.apply(.received(id: id, bytes: Int64(bytes), expectedBytes: nil, mimeType: nil))
    }

    let batch = try #require(await updates.next())
    #expect(batch.first?.bytesReceived == 50)
}

extension CaptureTests {
    @Suite struct Downloads {
        @Test func aRunningDownloadShowsProgressAndLeavesWhenItEnds() async throws {
            let handler: CaptureHarness.Handler = { _ in
                LocalHTTPServer.Response(body: Data(count: 50_000), delay: .milliseconds(600))
            }
            let configuration = CerebroConfiguration(
                consoleLevel: .off, redaction: RedactionRules(queryParameters: ["token"]))
            try await withCapture(configuration, handler: handler) { harness in
                let url = try #require(URL(string: harness.url("/slow.bin").absoluteString + "?token=hunter2"))
                async let finished = URLSession(configuration: .default).download(from: url)

                var running: DownloadProgress?
                for _ in 0..<500 where running == nil {
                    running = await harness.runtime.downloads.active.first
                    try await Task.sleep(for: .milliseconds(10))
                }
                #expect(running?.url?.path == "/slow.bin")
                #expect(running?.url?.absoluteString.contains("hunter2") == false)

                _ = try await finished
                let transaction = try await harness.transaction()
                #expect(transaction.response?.body?.content == .notStored)
                #expect(transaction.id == running?.id)
                for _ in 0..<500 where await !harness.runtime.downloads.active.isEmpty {
                    try await Task.sleep(for: .milliseconds(10))
                }
                #expect(await harness.runtime.downloads.active.isEmpty)
            }
        }

        @Test func anOrdinaryRequestIsNotADownload() async throws {
            try await withCapture { harness in
                _ = try await URLSession(configuration: .default).data(from: harness.url("/data"))

                _ = try await harness.transaction()
                #expect(await harness.runtime.downloads.active.isEmpty)
            }
        }
    }

    @Suite struct PublicIP {
        @Test func theLookupReturnsTheAddressAndStaysOutOfTheLogs() async throws {
            let handler: CaptureHarness.Handler = { _ in LocalHTTPServer.Response(body: Data("203.0.113.7\n".utf8)) }
            try await withCapture(handler: handler) { harness in
                let address = await PublicIPLookup(url: harness.url("/ip")).address()

                #expect(address == "203.0.113.7")
                #expect(harness.server.requests.count == 1)
                try await Task.sleep(for: .milliseconds(500))
                #expect(await harness.runtime.store.transactions.isEmpty)
            }
        }

        @Test func anAnswerThatIsntAnAddressIsRejected() async throws {
            let handler: CaptureHarness.Handler = { _ in
                LocalHTTPServer.Response(body: Data("<html>Sign in</html>".utf8))
            }
            try await withCapture(handler: handler) { harness in
                #expect(await PublicIPLookup(url: harness.url("/ip")).address() == nil)
            }
        }

        @Test func aFailedLookupReturnsNothing() async throws {
            let handler: CaptureHarness.Handler = { _ in LocalHTTPServer.Response(status: 500, reason: "Oops") }
            try await withCapture(handler: handler) { harness in
                #expect(await PublicIPLookup(url: harness.url("/ip")).address() == nil)
            }
        }

        @Test func withTheSettingOffNothingIsLookedUp() async throws {
            try await withCapture { harness in
                var updates = await harness.runtime.systemInfo.updates().makeAsyncIterator()
                let info = try #require(await updates.next())

                #expect(info.publicIP == .off)
            }
        }

        @Test func theMonitorPublishesTheAddressOnceItsOnline() async throws {
            let handler: CaptureHarness.Handler = { _ in LocalHTTPServer.Response(body: Data("203.0.113.7".utf8)) }
            try await withCapture(handler: handler) { harness in
                let monitor = SystemInfoMonitor(lookup: PublicIPLookup(url: harness.url("/ip")))
                defer { Task { await monitor.stop() } }

                var settled: SystemInfo?
                for await info in await monitor.updates() where info.publicIP != .loading {
                    settled = info
                    break
                }

                // A machine with no network never looks anything up.
                let expected: SystemInfo.PublicIP = settled?.status == .online ? .address("203.0.113.7") : .unavailable
                #expect(settled?.publicIP == expected)
                #expect(await harness.runtime.store.transactions.isEmpty)
            }
        }
    }
}
