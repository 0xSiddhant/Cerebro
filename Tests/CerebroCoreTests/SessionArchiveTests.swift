import Foundation
import Testing
import os
@testable import CerebroCore

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("cerebro-tests-\(UUID().uuidString)")
}

private func archive(
    in directory: URL,
    keeping previous: Int = 1,
    requests: Int = 500,
    fileBytes: Int = 50_000_000,
    at second: TimeInterval = 0
) -> SessionArchive {
    var limits = SessionArchive.Limits(requests: requests, socketFrames: 1_000, socketPayloadBytes: 1_000_000)
    limits.fileBytes = fileBytes
    return SessionArchive(
        directory: directory,
        previousSessionLimit: previous,
        limits: limits,
        startDate: Date(timeIntervalSince1970: 1_700_000_000 + second)
    )
}

private func files(in directory: URL) -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

private func requestLines(in file: URL) throws -> Int {
    try String(contentsOf: file, encoding: .utf8).split(separator: "\n").filter { $0.hasPrefix(#"{"http""#) }.count
}

private let socket = SocketIdentity(id: UUID(), source: .external, name: "wss://example.com/feed")

private func frame(_ text: String) -> SocketTimelineItem {
    .frame(
        SocketFrame(
            direction: .received,
            kind: .text,
            byteCount: text.utf8.count,
            date: Date(timeIntervalSince1970: 5),
            payload: CapturedBody(content: .complete(Data(text.utf8)), byteCount: text.utf8.count)
        )
    )
}

/// Saves `records` as one launch, then returns what the next launch finds.
private func savedSession(_ records: [SessionRecord], in directory: URL) async throws -> StoredSession {
    let first = archive(in: directory)
    records.forEach(first.append)
    await first.flush()
    let second = archive(in: directory, at: 60)
    let reference = try #require(await second.previousSessions().first)
    return await second.load(reference)
}

@Test func aSessionIsReadBackByTheNextLaunch() async throws {
    let directory = temporaryDirectory()
    let transactions = [Fixtures.transaction(path: "/a"), Fixtures.transaction(status: 500, path: "/b")]

    let session = try await savedSession(transactions.map(SessionRecord.http), in: directory)

    #expect(await session.store.transactions == transactions)
    #expect(session.reference.startDate == Date(timeIntervalSince1970: 1_700_000_000))
}

@Test func socketsAreReadBackWithTheirTimelineAndTotals() async throws {
    let records: [SessionRecord] = [
        .socket(socket, .event(.opened, date: Date(timeIntervalSince1970: 1))),
        .socket(socket, frame("hello")),
        .socket(socket, .event(.closed(code: 1_000, reason: "done"), date: Date(timeIntervalSince1970: 9))),
    ]

    let session = try await savedSession(records, in: temporaryDirectory())

    let connection = try #require(await session.socketStore.connections.first)
    #expect(connection.name == "wss://example.com/feed")
    #expect(connection.status == .closed)
    #expect(connection.frameCount == 1)
    #expect(connection.bytesReceived == 5)
    #expect(connection.timeline.count == 3)
}

@Test func everyKindOfBodySurvivesTheRoundTrip() async throws {
    let bodies = [
        CapturedBody(
            content: .complete(Data([0xFF, 0x00, 0x7F])), byteCount: 3, compression: .gzip, isDecompressed: true),
        CapturedBody(content: .truncated(Data("cut".utf8)), byteCount: 900, contentType: "text/plain"),
        CapturedBody(content: .withheld, byteCount: 40),
        CapturedBody(content: .notStored, byteCount: 4_096),
        CapturedBody(
            content: .complete(Data("{}".utf8)), byteCount: 9, isDecoded: true, rawData: Data([0x0A]), undecoded: nil),
        CapturedBody(content: .complete(Data([0x0A])), byteCount: 1, undecoded: .failed),
    ]
    let transactions = bodies.map { body in
        HTTPTransaction(
            request: CapturedRequest(
                url: URL(string: "https://example.com"), method: "POST",
                headers: [NamedValue(name: "A", value: "b")], body: body, startDate: Date(timeIntervalSince1970: 1)),
            response: CapturedResponse(
                statusCode: 200, body: body, mimeType: "x/y", endDate: Date(timeIntervalSince1970: 2)),
            failure: CapturedFailure(domain: "d", code: 3, description: "e"),
            timing: TransactionTiming(
                dns: 0.1, connect: 0.2, tls: 0.1, requestSent: 0.01, firstByte: 0.3, receive: 0.2, total: 1),
            connection: ConnectionDetails(
                remoteAddress: "1.2.3.4", remotePort: 443, httpVersion: "h2", isCellular: true),
            size: TransferSize(bytesSent: 1, bytesReceived: 2, wireBodyBytes: 3, decodedBodyBytes: 4)
        )
    }

    let session = try await savedSession(transactions.map(SessionRecord.http), in: temporaryDirectory())

    #expect(await session.store.transactions == transactions)
}

@Test func aLineCutShortByACrashIsSkipped() async throws {
    let directory = temporaryDirectory()
    let first = archive(in: directory)
    first.append(.http(Fixtures.transaction(path: "/whole")))
    await first.flush()
    let file = try #require(files(in: directory).first)
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"http":{"_0":{"id":"#.utf8))
    try handle.close()

    let second = archive(in: directory, at: 60)
    let session = await second.load(try #require(await second.previousSessions().first))

    #expect(await session.store.transactions.map { $0.request.url?.path } == ["/whole"])
}

@Test func clearingTheListIsReplayedSoClearedRequestsStayGone() async throws {
    let records: [SessionRecord] = [
        .http(Fixtures.transaction(path: "/before")), .httpCleared, .http(Fixtures.transaction(path: "/after")),
    ]

    let session = try await savedSession(records, in: temporaryDirectory())

    #expect(await session.store.transactions.map { $0.request.url?.path } == ["/after"])
}

@Test func onlyTheConfiguredNumberOfEarlierSessionsIsKept() async {
    let directory = temporaryDirectory()
    for launch in 0..<4 {
        await archive(in: directory, keeping: 1, at: TimeInterval(launch * 60)).flush()
    }

    let latest = archive(in: directory, keeping: 1, at: 600)

    #expect(await latest.previousSessions().map(\.startDate) == [Date(timeIntervalSince1970: 1_700_000_180)])
    #expect(files(in: directory).count == 2)
}

@Test func severalEarlierSessionsCanBeKeptNewestFirst() async {
    let directory = temporaryDirectory()
    for launch in 0..<4 {
        await archive(in: directory, keeping: 3, at: TimeInterval(launch * 60)).flush()
    }

    let previous = await archive(in: directory, keeping: 3, at: 600).previousSessions()

    #expect(previous.map(\.startDate.timeIntervalSince1970) == [1_700_000_180, 1_700_000_120, 1_700_000_060])
}

@Test func keepingNoEarlierSessionsLeavesOnlyThisLaunch() async {
    let directory = temporaryDirectory()
    await archive(in: directory, keeping: 0).flush()

    let latest = archive(in: directory, keeping: 0, at: 60)

    #expect(await latest.previousSessions().isEmpty)
    #expect(files(in: directory).count == 1)
}

@Test func otherFilesInTheFolderAreLeftAlone() async throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let stray = directory.appendingPathComponent("notes.txt")
    try Data("mine".utf8).write(to: stray)

    let latest = archive(in: directory, keeping: 0)

    #expect(await latest.previousSessions().isEmpty)
    #expect(FileManager.default.fileExists(atPath: stray.path))
}

@Test func theFileKeepsOnlyAsManyRequestsAsTheStore() async throws {
    let directory = temporaryDirectory()
    let limited = archive(in: directory, requests: 3)

    for index in 0..<7 {
        limited.append(.http(Fixtures.transaction(path: "/\(index)")))
    }
    await limited.flush()

    let file = try #require(files(in: directory).first)
    #expect(try requestLines(in: file) == 3)
    let next = archive(in: directory, requests: 3, at: 60)
    let session = await next.load(try #require(await next.previousSessions().first))
    #expect(await session.store.transactions.map { $0.request.url?.path } == ["/4", "/5", "/6"])
}

@Test func theFileStaysUnderItsByteLimitAndKeepsTheNewest() async throws {
    let directory = temporaryDirectory()
    let limited = archive(in: directory, fileBytes: 20_000)
    let body = CapturedBody(content: .complete(Data(count: 1_500)), byteCount: 1_500)

    for index in 0..<40 {
        let request = CapturedRequest(
            url: URL(string: "https://example.com/\(index)"), method: "POST", body: body, startDate: Date())
        limited.append(.http(HTTPTransaction(request: request)))
    }
    await limited.flush()

    let file = try #require(files(in: directory).first)
    let size = try #require(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize)
    #expect(size <= 20_000)
    let next = archive(in: directory, fileBytes: 20_000, at: 60)
    let session = await next.load(try #require(await next.previousSessions().first))
    #expect(await session.store.transactions.last?.request.url?.path == "/39")
    #expect(await session.store.transactions.count < 40)
}

@Test func writingContinuesAfterTheFileIsTrimmed() async throws {
    let directory = temporaryDirectory()
    let limited = archive(in: directory, requests: 2)
    for index in 0..<5 {
        limited.append(.http(Fixtures.transaction(path: "/\(index)")))
    }
    await limited.flush()

    limited.append(.http(Fixtures.transaction(path: "/late")))
    await limited.flush()

    let text = try String(contentsOf: try #require(files(in: directory).first), encoding: .utf8)
    #expect(text.hasPrefix(#"{"header""#))
    #expect(text.contains("/late"))
}

@Test @MainActor func writesNeverRunOnTheMainThread() async {
    let ranOnMain = OSAllocatedUnfairLock(initialState: [Bool]())
    let limits = SessionArchive.Limits(requests: 10, socketFrames: 10, socketPayloadBytes: 1_000)
    let archive = SessionArchive(directory: temporaryDirectory(), previousSessionLimit: 1, limits: limits) {
        ranOnMain.withLock { $0.append(Thread.isMainThread) }
    }

    archive.append(.http(Fixtures.transaction()))
    await archive.flush()

    #expect(ranOnMain.withLock { $0 } == [false, false])
}

extension CaptureTests {
    @Suite struct Persistence {
        @Test func aCapturedSessionIsThereAfterARelaunchAlreadyRedacted() async throws {
            let directory = temporaryDirectory()
            let server = try LocalHTTPServer { _ in LocalHTTPServer.Response(body: Data(#"{"ok":true}"#.utf8)) }
            let baseURL = try await server.start()
            defer { server.stop() }
            let rules = RedactionRules(headers: ["X-Secret"], jsonKeys: ["password"], queryParameters: ["token"])
            let configuration = CerebroConfiguration(consoleLevel: .off, redaction: rules)

            let first = CaptureRuntime(unchecked: configuration, sessionsDirectory: directory)
            first.start()
            var request = URLRequest(url: try #require(URL(string: baseURL.absoluteString + "/login?token=hunter2")))
            request.httpMethod = "POST"
            request.setValue("hunter2", forHTTPHeaderField: "X-Secret")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data(#"{"password":"hunter2","user":"ada"}"#.utf8)
            _ = try await URLSession(configuration: .default).data(for: request)
            for _ in 0..<1_500 where await first.store.transactions.isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
            first.stop()
            await first.archive?.flush()

            let onDisk = try String(contentsOf: try #require(files(in: directory).first), encoding: .utf8)
            #expect(!onDisk.contains("hunter2"))
            #expect(!onDisk.contains(Data("hunter2".utf8).base64EncodedString()))

            let second = CaptureRuntime(unchecked: configuration, sessionsDirectory: directory)
            let archive = try #require(second.archive)
            let session = await archive.load(try #require(await archive.previousSessions().first))
            let restored = try #require(await session.store.transactions.first)
            #expect(restored.request.url?.path == "/login")
            #expect(restored.response?.statusCode == 200)
            #expect(restored.request.headers.first { $0.name == "X-Secret" }?.value == Redactor.marker)
            let body = try #require(restored.request.body?.data)
            #expect(String(data: body, encoding: .utf8)?.contains("ada") == true)
        }

        @Test func withPersistenceOffNothingIsWrittenAndEarlierSessionsAreRemoved() async throws {
            let directory = temporaryDirectory()
            await archive(in: directory).flush()
            #expect(files(in: directory).count == 1)

            let configuration = CerebroConfiguration(consoleLevel: .off, isPersistenceEnabled: false)
            let runtime = CaptureRuntime(unchecked: configuration, sessionsDirectory: directory)
            await runtime.store.append(Fixtures.transaction())

            #expect(runtime.archive == nil)
            for _ in 0..<500 where FileManager.default.fileExists(atPath: directory.path) {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(!FileManager.default.fileExists(atPath: directory.path))
        }

        @Test func socketsAreSavedAsTheyHappen() async throws {
            let directory = temporaryDirectory()
            let runtime = CaptureRuntime(
                unchecked: CerebroConfiguration(consoleLevel: .off), sessionsDirectory: directory)
            runtime.start()
            let connection = ExternalNetworkBridge.Connection(name: "Prices")
            ExternalNetworkBridge.log(.opened, on: connection)
            ExternalNetworkBridge.log(.text("tick"), .received, on: connection)
            for _ in 0..<1_500 where await runtime.socketStore.connections.first?.frameCount != 1 {
                try await Task.sleep(for: .milliseconds(10))
            }
            runtime.stop()
            await runtime.archive?.flush()

            let next = archive(in: directory, at: 4_000_000_000)
            let session = await next.load(try #require(await next.previousSessions().first))

            let saved = try #require(await session.socketStore.connections.first)
            #expect(saved.name == "Prices")
            #expect(saved.frameCount == 1)
        }
    }
}

@Test func aFinishedStreamIsReadBackWithItsEvents() async throws {
    let directory = temporaryDirectory()
    let stream = Fixtures.stream(.completed, events: [Fixtures.event("one", id: "7", type: "tick")])

    let session = try await savedSession([.http(stream)], in: directory)

    #expect(await session.store.transactions == [stream])
}

@Test func aRecordSavedBeforeEventStreamsStillDecodes() throws {
    // A line as 1.0 wrote it, which has no `eventStream` key.
    let line = Data(
        #"""
        {"http":{"_0":{"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","request":{"url":"https://example.com/a",\#
        "method":"GET","headers":[],"queryParameters":[],"startDate":0},"response":{"statusCode":200,\#
        "headers":[],"endDate":1}}}}
        """#.utf8)

    let record = try JSONDecoder().decode(SessionRecord.self, from: line)

    guard case .http(let transaction) = record else {
        Issue.record("expected a request, got \(record)")
        return
    }
    #expect(transaction.response?.statusCode == 200)
    #expect(transaction.eventStream == nil)
    #expect(!transaction.isOpen)
}

@Test func aTransactionWithoutAStreamEncodesAsItDidBefore() throws {
    let encoded = try JSONEncoder().encode(SessionRecord.http(Fixtures.transaction()))

    #expect(String(data: encoded, encoding: .utf8)?.contains("eventStream") == false)
}
