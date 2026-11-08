import os

/// Limits what can wait for the pipeline. A frame that doesn't fit keeps only its size, so a slow
/// moment can't exhaust memory, and events always get through so a socket can't get stuck open.
final class SocketBacklog: Sendable {
    private struct Usage {
        var frames = 0
        var bytes = 0
    }

    private let usage = OSAllocatedUnfairLock(initialState: Usage())
    private let frameLimit: Int
    private let byteLimit: Int

    init(frameLimit: Int, byteLimit: Int) {
        self.frameLimit = frameLimit
        self.byteLimit = byteLimit
    }

    /// Returns whether a payload of this size may wait, and counts it if so.
    func admit(bytes: Int) -> Bool {
        usage.withLock { usage in
            guard usage.frames < frameLimit, bytes <= byteLimit - usage.bytes else { return false }
            usage.frames += 1
            usage.bytes += bytes
            return true
        }
    }

    /// Call when a queued frame has left the pipeline. `bytes` of zero means it held no payload.
    func finish(bytes: Int) {
        guard bytes > 0 else { return }
        usage.withLock { usage in
            usage.frames -= 1
            usage.bytes -= bytes
        }
    }
}
