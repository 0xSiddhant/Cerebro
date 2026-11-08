import Foundation
import Testing
@testable import CerebroCore

private func value(of name: String, in fields: [NamedValue]) -> String? {
    fields.first { $0.name == name }?.value
}

@Test func redactsTheFourDefaultHeadersWithNoConfiguration() {
    let fields = Redactor(rules: RedactionRules()).redact(headers: [
        "Authorization": "Bearer secret",
        "proxy-authorization": "secret",
        "COOKIE": "session=secret",
        "Set-Cookie": "session=secret",
        "Accept": "application/json",
    ])

    #expect(value(of: "Authorization", in: fields) == Redactor.marker)
    #expect(value(of: "proxy-authorization", in: fields) == Redactor.marker)
    #expect(value(of: "COOKIE", in: fields) == Redactor.marker)
    #expect(value(of: "Set-Cookie", in: fields) == Redactor.marker)
    #expect(value(of: "Accept", in: fields) == "application/json")
}

@Test func redactsConfiguredHeadersWhateverTheirCase() {
    let redactor = Redactor(rules: RedactionRules(headers: ["X-Api-Key"]))

    let fields = redactor.redact(headers: ["x-api-key": "secret"])

    #expect(value(of: "x-api-key", in: fields) == Redactor.marker)
}

@Test func redactsConfiguredQueryParameters() throws {
    let redactor = Redactor(rules: RedactionRules(queryParameters: ["token"]))
    let url = URL(string: "https://example.com/a?token=secret&page=2")

    let redacted = try #require(redactor.redact(url: url))

    #expect(!redacted.absoluteString.contains("secret"))
    #expect(redacted.absoluteString.contains("page=2"))
    #expect(value(of: "token", in: redactor.queryParameters(of: redacted)) == Redactor.marker)
    #expect(value(of: "page", in: redactor.queryParameters(of: redacted)) == "2")
}

@Test func leavesURLsAloneWithNoRules() {
    let url = URL(string: "https://example.com/a?token=secret")

    #expect(Redactor(rules: RedactionRules()).redact(url: url) == url)
}

@Test func redactsJSONKeysAtAnyDepth() throws {
    let redactor = Redactor(rules: RedactionRules(jsonKeys: ["password"]))
    let json: [String: Any] = ["user": ["Password": "secret", "name": "ada"], "list": [["password": "secret"]]]

    let output = try JSONSerialization.data(withJSONObject: redactor.redact(json: json))
    let text = try #require(String(data: output, encoding: .utf8))

    #expect(!text.contains("secret"))
    #expect(text.contains("ada"))
}
