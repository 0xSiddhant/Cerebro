import Foundation
import Testing
@testable import CerebroCore

private let text = Data(String(repeating: "cerebro ", count: 1_000).utf8)

@Test func readsGzip() throws {
    let output = Decompressor.decompress(try Fixtures.gzip(text), as: .gzip, limit: 1_000_000)

    #expect(output == Decompressor.Output(data: text, isTruncated: false))
}

@Test func readsZlib() throws {
    let output = Decompressor.decompress(try Fixtures.zlib(text), as: .zlib, limit: 1_000_000)

    #expect(output == Decompressor.Output(data: text, isTruncated: false))
}

@Test func readsGzipWithANameInItsHeader() throws {
    let deflated = try (text as NSData).compressed(using: .zlib) as Data
    let header = Data([0x1F, 0x8B, 0x08, 0x08, 0, 0, 0, 0, 0, 0xFF]) + Data("body.json".utf8) + Data([0])

    let output = Decompressor.decompress(header + deflated + Data(count: 8), as: .gzip, limit: 1_000_000)

    #expect(output?.data == text)
}

@Test func spotsCompressionFromMagicBytes() throws {
    #expect(Decompressor.compression(fromMagicBytes: try Fixtures.gzip(text)) == .gzip)
    #expect(Decompressor.compression(fromMagicBytes: try Fixtures.zlib(text)) == .zlib)
    #expect(Decompressor.compression(fromMagicBytes: Data([0x28, 0xB5, 0x2F, 0xFD, 0x00])) == .zstd)
    #expect(Decompressor.compression(fromMagicBytes: Data("{\"plain\":true}".utf8)) == nil)
}

@Test func spotsCompressionFromContentEncoding() {
    #expect(Decompressor.compression(fromContentEncoding: "gzip") == .gzip)
    #expect(Decompressor.compression(fromContentEncoding: " Deflate ") == .zlib)
    #expect(Decompressor.compression(fromContentEncoding: "br") == .brotli)
    #expect(Decompressor.compression(fromContentEncoding: "zstd") == .zstd)
    #expect(Decompressor.compression(fromContentEncoding: "identity") == nil)
    #expect(Decompressor.compression(fromContentEncoding: nil) == nil)
}

@Test func stopsAtTheLimitWhenASmallBodyExpandsFarPastIt() throws {
    let huge = Data(count: 200_000_000)
    let bomb = try Fixtures.gzip(huge)
    #expect(bomb.count < 1_000_000)

    let output = try #require(Decompressor.decompress(bomb, as: .gzip, limit: 1_000_000))

    #expect(output.data.count == 1_000_000)
    #expect(output.isTruncated)
}

@Test func keepsWhatItCanFromATruncatedStream() throws {
    let random = Data((0..<200_000).map { _ in UInt8.random(in: 0...255) })
    let compressed = try Fixtures.gzip(random)

    let output = Decompressor.decompress(compressed.prefix(50_000), as: .gzip, limit: 1_000_000)

    #expect(output?.data.isEmpty == false)
    #expect(output?.isTruncated == true)
}

@Test func returnsNothingForBytesThatAreNotCompressed() {
    #expect(Decompressor.decompress(Data("not compressed at all".utf8), as: .gzip, limit: 1_000) == nil)
    #expect(Decompressor.decompress(Data(count: 2), as: .zlib, limit: 1_000) == nil)
}

@Test func neverTriesToReadFormatsItCantDecode() {
    #expect(Decompressor.decompress(Data([0x28, 0xB5, 0x2F, 0xFD, 0x00]), as: .zstd, limit: 1_000) == nil)
    #expect(Decompressor.decompress(Data("anything".utf8), as: .brotli, limit: 1_000) == nil)
}
