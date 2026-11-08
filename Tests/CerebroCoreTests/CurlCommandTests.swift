import Foundation
import Testing
@testable import CerebroCore

private func request(
    method: String = "GET",
    url: String = "https://example.com/a?b=1",
    headers: [NamedValue] = [],
    body: CapturedBody? = nil
) -> CapturedRequest {
    CapturedRequest(
        url: URL(string: url),
        method: method,
        headers: headers,
        body: body,
        startDate: Date(timeIntervalSince1970: 0)
    )
}

private func textBody(_ text: String) -> CapturedBody {
    CapturedBody(content: .complete(Data(text.utf8)), byteCount: text.utf8.count)
}

@Test func plainGetIsJustTheURL() {
    let command = CurlCommand(request: request())

    #expect(command.text == "curl 'https://example.com/a?b=1'")
    #expect(command.caveats.isEmpty)
}

@Test func postCarriesItsMethodHeadersAndBody() {
    let command = CurlCommand(
        request: request(
            method: "POST",
            headers: [NamedValue(name: "Content-Type", value: "application/json")],
            body: textBody("{\"a\":1}")
        )
    )

    #expect(
        command.text == """
            curl -X POST 'https://example.com/a?b=1' \\
              -H 'Content-Type: application/json' \\
              --data-raw '{"a":1}'
            """
    )
    #expect(command.caveats.isEmpty)
}

@Test func headUsesTheHeadOption() {
    #expect(CurlCommand(request: request(method: "HEAD")).text == "curl --head 'https://example.com/a?b=1'")
}

@Test func getWithABodyNamesItsMethod() {
    #expect(CurlCommand(request: request(body: textBody("x"))).text.hasPrefix("curl -X GET "))
}

@Test func singleQuotesAreEscapedForTheShell() {
    let command = CurlCommand(
        request: request(
            method: "POST",
            headers: [NamedValue(name: "X-Note", value: "it's")],
            body: textBody("a'b")
        )
    )

    #expect(command.text.contains(#"-H 'X-Note: it'\''s'"#))
    #expect(command.text.contains(#"--data-raw 'a'\''b'"#))
}

@Test func emptyHeaderUsesTheSemicolonForm() {
    let command = CurlCommand(request: request(headers: [NamedValue(name: "X-Empty", value: "")]))

    #expect(command.text.contains("-H 'X-Empty;'"))
}

@Test func contentLengthIsLeftToCurl() {
    let command = CurlCommand(request: request(headers: [NamedValue(name: "content-LENGTH", value: "9")]))

    #expect(!command.text.lowercased().contains("content-length"))
}

@Test func decompressedBodyDropsItsContentEncoding() {
    let decompressed = CapturedBody(
        content: .complete(Data("x".utf8)), byteCount: 1, compression: .gzip, isDecompressed: true)
    let headers = [NamedValue(name: "Content-Encoding", value: "gzip")]

    #expect(!CurlCommand(request: request(headers: headers, body: decompressed)).text.contains("Content-Encoding"))
    #expect(CurlCommand(request: request(headers: headers, body: textBody("x"))).text.contains("Content-Encoding"))
}

@Test func truncatedBodyIsSentAndFlagged() {
    let body = CapturedBody(content: .truncated(Data("start".utf8)), byteCount: 9_000_000)

    let command = CurlCommand(request: request(method: "POST", body: body))

    #expect(command.text.contains("--data-raw 'start'"))
    #expect(command.caveats == ["The body was cut off at capture, so it's incomplete."])
}

@Test func withheldBodyIsLeftOutAndFlagged() {
    let command = CurlCommand(request: request(method: "POST", body: CapturedBody(content: .withheld, byteCount: 3)))

    #expect(!command.text.contains("--data-raw"))
    #expect(command.caveats == ["The body isn't included, because it couldn't be redacted."])
}

private func bytesBody(_ bytes: [UInt8]) -> CapturedBody {
    CapturedBody(content: .complete(Data(bytes)), byteCount: bytes.count)
}

@Test func protobufStyleBytesArePipedInAsBase64() {
    // Valid UTF-8, but the control characters wouldn't survive being pasted into a terminal.
    let command = CurlCommand(request: request(method: "POST", body: bytesBody([0x0A, 0x20, 0x08, 0x41])))

    #expect(
        command.text == """
            printf %s 'CiAIQQ==' | base64 --decode | curl -X POST 'https://example.com/a?b=1' \\
              --data-binary @-
            """
    )
    #expect(command.caveats.isEmpty)
}

@Test func bytesThatArentUTF8ArePipedInAsBase64() {
    let command = CurlCommand(request: request(method: "POST", body: bytesBody([0x00, 0xFF])))

    #expect(command.text.hasPrefix("printf %s 'AP8=' | base64 --decode | curl -X POST "))
    #expect(command.text.hasSuffix("--data-binary @-"))
    #expect(command.caveats.isEmpty)
}

@Test func carriageReturnsArePipedInSoMultipartBodiesKeepThem() {
    let command = CurlCommand(request: request(method: "POST", body: textBody("a\r\nb")))

    #expect(command.text.hasPrefix("printf %s 'YQ0KYg==' | base64 --decode | "))
}

@Test func multiLineAndUnicodeTextStaysReadable() {
    let command = CurlCommand(request: request(method: "POST", body: textBody("{\n  \"a\": \"héllo\"\n}")))

    #expect(command.text.hasPrefix("curl -X POST "))
    #expect(command.text.hasSuffix("--data-raw '{\n  \"a\": \"héllo\"\n}'"))
}

@Test func textTooLongForAnArgumentIsPipedInAndStaysReadable() {
    let longest = String(repeating: "a", count: 100_000)

    let atLimit = CurlCommand(request: request(method: "POST", body: textBody(longest)))
    let overLimit = CurlCommand(request: request(method: "POST", body: textBody(longest + "a")))

    #expect(atLimit.text.contains("--data-raw 'aaa"))
    #expect(overLimit.text.hasPrefix("printf %s 'aaa"))
    #expect(overLimit.text.contains("' | curl -X POST "))
    #expect(!overLimit.text.contains("base64"))
    #expect(overLimit.text.hasSuffix("--data-binary @-"))
}

@Test func truncatedBinaryBodyIsPipedInAndFlagged() {
    let body = CapturedBody(content: .truncated(Data([0x00, 0xFF])), byteCount: 9_000_000)

    let command = CurlCommand(request: request(method: "POST", body: body))

    #expect(command.text.hasPrefix("printf %s 'AP8=' | base64 --decode | "))
    #expect(command.caveats == ["The body was cut off at capture, so it's incomplete."])
}

@Test func redactedValuesStayPlaceholdersAndAreFlagged() {
    let command = CurlCommand(request: request(headers: [NamedValue(name: "Authorization", value: Redactor.marker)]))

    #expect(command.text.contains("Authorization: [redacted]"))
    #expect(command.caveats == ["Redacted values are placeholders."])
}
