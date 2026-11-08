import Foundation
import Testing
@testable import CerebroCore

@Test func formatsJSONWithIndentation() throws {
    let pretty = try #require(BodyFormatter.prettyJSON(Data(#"{"b":1,"a":"x/y"}"#.utf8)))

    #expect(pretty == "{\n  \"a\" : \"x/y\",\n  \"b\" : 1\n}")
}

@Test func returnsNothingForInvalidJSON() {
    #expect(BodyFormatter.prettyJSON(Data("{not json".utf8)) == nil)
}

@Test func readsTextAsUTF8() {
    #expect(BodyFormatter.text(Data("héllo".utf8)) == "héllo")
}

@Test func fallsBackToHexForBinary() {
    #expect(BodyFormatter.text(Data([0xFF, 0x00, 0xAB])) == "ff00ab")
}
