import Foundation
import Testing
@testable import CerebroCore

private func value(of name: String, in fields: [NamedValue]) -> String? {
    fields.first { $0.name == name }?.value
}

@Test func redactsNoHeaderWithNoConfiguration() {
    let sent = Dictionary(uniqueKeysWithValues: SensitiveHeader.allCases.map { ($0.rawValue, "secret") })

    let fields = Redactor(rules: RedactionRules()).redact(headers: sent)

    #expect(fields.count == SensitiveHeader.allCases.count)
    #expect(fields.allSatisfy { $0.value == "secret" })
}

@Test func redactsEverySelectedHeaderWhateverItsCase() {
    var sent = Dictionary(uniqueKeysWithValues: SensitiveHeader.allCases.map { ($0.rawValue, "secret") })
    sent["authorization"] = sent.removeValue(forKey: SensitiveHeader.authorization.rawValue)
    sent["Accept"] = "application/json"
    let redactor = Redactor(rules: RedactionRules(sensitiveHeaders: Set(SensitiveHeader.allCases)))

    let fields = redactor.redact(headers: sent)

    #expect(fields.count == SensitiveHeader.allCases.count + 1)
    #expect(value(of: "authorization", in: fields) == Redactor.marker)
    #expect(fields.filter { $0.name != "Accept" }.allSatisfy { $0.value == Redactor.marker })
    #expect(value(of: "Accept", in: fields) == "application/json")
}

@Test func redactsOnlyTheSelectedHeaders() {
    let redactor = Redactor(rules: RedactionRules(sensitiveHeaders: [.authorization]))

    let fields = redactor.redact(headers: ["Authorization": "secret", "Cookie": "session=kept"])

    #expect(value(of: "Authorization", in: fields) == Redactor.marker)
    #expect(value(of: "Cookie", in: fields) == "session=kept")
}

@Test func aNameInHeadersIsRedactedWithOrWithoutItsCase() {
    let without = Redactor(rules: RedactionRules(sensitiveHeaders: [.cookie], headers: ["Authorization"]))
    let with = Redactor(rules: RedactionRules(sensitiveHeaders: [.authorization], headers: ["Authorization"]))

    #expect(value(of: "Authorization", in: without.redact(headers: ["Authorization": "secret"])) == Redactor.marker)
    #expect(value(of: "Authorization", in: with.redact(headers: ["Authorization": "secret"])) == Redactor.marker)
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
