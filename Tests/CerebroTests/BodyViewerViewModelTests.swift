import Foundation
import Testing
@testable import Cerebro

@MainActor
private func viewModel(_ text: String) -> BodyViewerViewModel {
    BodyViewerViewModel(
        title: "Body", body: CapturedBody(content: .complete(Data(text.utf8)), byteCount: text.utf8.count))
}

@Test @MainActor func prettyModeFormatsJSON() async {
    #expect(await viewModel(#"{"a":1}"#).text(for: .pretty) == "{\n  \"a\" : 1\n}")
}

@Test @MainActor func rawModeLeavesTheBodyAlone() async {
    #expect(await viewModel(#"{"a":1}"#).text(for: .raw) == #"{"a":1}"#)
}

@Test @MainActor func prettyModeFallsBackToRawForAnythingElse() async {
    #expect(await viewModel("plain text").text(for: .pretty) == "plain text")
}

@Test @MainActor func truncatedJSONStillShowsAsText() async {
    let body = CapturedBody(content: .truncated(Data(#"{"a":"#.utf8)), byteCount: 100)

    #expect(await BodyViewerViewModel(title: "Body", body: body).text(for: .pretty) == #"{"a":"#)
}

@Test @MainActor func fileNameFollowsTheTitleAndContent() {
    let json = CapturedBody(content: .complete(Data("  {\"a\":1}".utf8)), byteCount: 8)
    let plain = CapturedBody(content: .complete(Data("hello".utf8)), byteCount: 5)

    #expect(BodyViewerViewModel(title: "Response body", body: json).fileName == "response-body.json")
    #expect(BodyViewerViewModel(title: "Request body", body: plain).fileName == "request-body.txt")
}

@Test @MainActor func copyMessageWarnsAboutATruncatedBody() {
    let whole = CapturedBody(content: .complete(Data("a".utf8)), byteCount: 1)
    let cut = CapturedBody(content: .truncated(Data("a".utf8)), byteCount: 9)

    #expect(BodyViewerViewModel(title: "Body", body: whole).copyMessage == "Copied.")
    #expect(BodyViewerViewModel(title: "Body", body: cut).copyMessage.contains("cut off"))
}

private let decodedJSON = Data(#"{"a":1}"#.utf8)

@Test @MainActor func aDecodedBodyOffersATreeAndOpensThere() {
    let body = CapturedBody(
        content: .complete(decodedJSON), byteCount: 4, isDecoded: true, rawData: Data([0x08, 0x01]))

    #expect(BodyViewerViewModel(title: "Body", body: body).modes == [.tree, .pretty, .raw])
}

@Test @MainActor func anOrdinaryBodyHasNoTree() {
    #expect(viewModel(#"{"a":1}"#).modes == [.pretty, .raw])
}

@Test @MainActor func aDecodedBodyShowsItsOriginalBytesAsHex() async {
    let body = CapturedBody(
        content: .complete(decodedJSON), byteCount: 2, isDecoded: true, rawData: Data([0x08, 0x01]))

    #expect(await BodyViewerViewModel(title: "Body", body: body).text(for: .raw) == "0801")
}

@Test @MainActor func aDecodedBodyWhoseBytesWereDroppedShowsOnlyItsRedactedJSON() async {
    let body = CapturedBody(content: .complete(Data(#"{"a":"[redacted]"}"#.utf8)), byteCount: 2, isDecoded: true)

    #expect(await BodyViewerViewModel(title: "Body", body: body).text(for: .raw) == #"{"a":"[redacted]"}"#)
}

@Test @MainActor func undecodedProtobufShowsAsHexInEveryMode() async {
    let body = CapturedBody(content: .complete(Data("123".utf8)), byteCount: 3, undecoded: .noRule)
    let model = BodyViewerViewModel(title: "Body", body: body)

    #expect(await model.text(for: .raw) == "313233")
    #expect(await model.text(for: .pretty) == "313233")
}

@Test @MainActor func treeIsBuiltFromTheStoredJSON() async throws {
    let body = CapturedBody(content: .complete(decodedJSON), byteCount: 2, isDecoded: true)

    let tree = try #require(await BodyViewerViewModel(title: "Body", body: body).tree())

    #expect(tree.rows.map(\.value) == ["{1}", "1"])
}
