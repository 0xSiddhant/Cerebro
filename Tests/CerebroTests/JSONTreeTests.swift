import Foundation
import Testing
@testable import Cerebro

private func tree(_ json: String) throws -> JSONTree {
    try #require(JSONTree(json: Data(json.utf8)))
}

@Test func bytesThatArentJSONHaveNoTree() {
    #expect(JSONTree(json: Data([0xFF, 0x00])) == nil)
}

@Test func valuesAreWrittenByType() throws {
    let rows = try tree(#"{"a":"x","b":1.5,"c":true,"d":null,"e":{},"f":[]}"#).rows

    #expect(rows.map(\.key) == [nil, "a", "b", "c", "d", "e", "f"])
    #expect(rows.map(\.value) == ["{6}", #""x""#, "1.5", "true", "null", "{0}", "[0]"])
}

@Test func aBareValueIsOneRow() throws {
    let rows = try tree("42").rows

    #expect(rows.map(\.value) == ["42"])
    #expect(rows.first?.canExpand == false)
}

@Test func arrayItemsAreKeyedByPosition() throws {
    #expect(try tree(#"["x","y"]"#).rows.map(\.key) == [nil, "0", "1"])
}

@Test func keysAreSorted() throws {
    #expect(try tree(#"{"b":1,"a":2}"#).rows.compactMap(\.key) == ["a", "b"])
}

@Test func theTopTwoLevelsStartOpenAndDeeperOnesFolded() throws {
    let rows = try tree(#"{"a":{"b":{"c":1}}}"#).rows

    #expect(rows.map(\.key) == [nil, "a", "b"])
    #expect(rows.map(\.isExpanded) == [true, true, false])
}

@Test func anEmptyContainerCantExpand() throws {
    #expect(try tree(#"{"a":{}}"#).rows.last?.canExpand == false)
}

@Test func depthFollowsNesting() throws {
    #expect(try tree(#"{"a":{"b":1}}"#).rows.map(\.depth) == [0, 1, 2])
}

@Test func foldingHidesEverythingBeneathARow() throws {
    var tree = try tree(#"{"a":{"b":1,"c":2},"d":3}"#)

    tree.toggle(rowAt: 1)

    #expect(tree.rows.map(\.key) == [nil, "a", "d"])
    #expect(tree.rows[1].isExpanded == false)
}

@Test func unfoldingBringsRowsBack() throws {
    var tree = try tree(#"{"a":{"b":1},"d":3}"#)

    tree.toggle(rowAt: 1)
    tree.toggle(rowAt: 1)

    #expect(tree.rows.map(\.key) == [nil, "a", "b", "d"])
}

@Test func unfoldingADeepRowRevealsItsChildren() throws {
    var tree = try tree(#"{"a":{"b":{"c":1}}}"#)

    tree.toggle(rowAt: 2)

    #expect(tree.rows.map(\.key) == [nil, "a", "b", "c"])
}

@Test func togglingALeafOrAnInvalidRowDoesNothing() throws {
    var tree = try tree(#"{"a":1}"#)
    let before = tree.rows

    tree.toggle(rowAt: 1)
    tree.toggle(rowAt: 99)

    #expect(tree.rows == before)
}
