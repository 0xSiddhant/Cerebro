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
