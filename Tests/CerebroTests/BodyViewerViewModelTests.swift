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
