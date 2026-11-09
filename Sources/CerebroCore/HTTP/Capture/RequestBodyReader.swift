import Foundation

/// Reads a request's body out of its stream, since URLProtocol only ever receives bodies as streams.
///
/// A body within the cap stays in memory. A bigger one spools to a temporary file, which keeps memory
/// bounded and lets URLSession send the same `Content-Length` it would have sent.
enum RequestBodyReader {
    /// What to send, and what was kept for display.
    struct Output {
        let captured: RawBody
        let spooledFile: URL?
        let error: (any Error)?
    }

    private static let chunkSize = 65_536

    static func read(_ stream: InputStream, limit: Int) -> Output {
        stream.open()
        defer { stream.close() }

        var captured = RawBody(limit: limit)
        var writer: FileHandle?
        var spooledFile: URL?
        var chunk = [UInt8](repeating: 0, count: chunkSize)
        do {
            while true {
                let count = stream.read(&chunk, maxLength: chunkSize)
                if count < 0, let error = stream.streamError {
                    throw error
                }
                guard count > 0 else { break }
                let bytes = Data(chunk[..<count])
                if writer == nil, captured.byteCount + count > limit {
                    let file = try makeSpoolFile(startingWith: captured.data)
                    spooledFile = file
                    writer = try FileHandle(forWritingTo: file)
                    try writer?.seekToEnd()
                }
                try writer?.write(contentsOf: bytes)
                captured.append(bytes)
            }
        } catch {
            try? writer?.close()
            spooledFile.map(remove)
            return Output(captured: captured, spooledFile: nil, error: error)
        }
        try? writer?.close()
        return Output(captured: captured, spooledFile: spooledFile, error: nil)
    }

    static func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
    }

    private static func makeSpoolFile(startingWith data: Data) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cerebro-upload-\(UUID().uuidString)")
        try data.write(to: file)
        return file
    }
}
