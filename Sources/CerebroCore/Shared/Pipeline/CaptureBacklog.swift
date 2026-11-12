import os

/// Limits the payload that can wait for the pipeline, so a slow moment can't exhaust memory. Sockets
/// share one, and each event stream has its own. A payload that doesn't fit is dropped by its caller,
/// while events and completions hold no payload and always get through, so nothing gets stuck open.
final class CaptureBacklog: Sendable {
    private struct Usage {
        var frames = 0
        var bytes = 0
    }

    private let usage = OSAllocatedUnfairLock(initialState: Usage())
    private let frameLimit: Int
    private let byteLimit: Int

    init(frameLimit: Int = .max, byteLimit: Int) {
        self.frameLimit = frameLimit
        self.byteLimit = byteLimit
    }

    /// Returns whether a payload of this size may wait, and counts it if so.
    ///
    /// `evenIfAlone` lets one payload wait whatever its size while nothing else does. An event stream
    /// uses it, because a chunk the network delivered whole isn't a sign that parsing has fallen behind.
    func admit(bytes: Int, evenIfAlone: Bool = false) -> Bool {
        usage.withLock { usage in
            let fits = usage.frames < frameLimit && bytes <= byteLimit - usage.bytes
            guard fits || (evenIfAlone && usage.bytes == 0) else { return false }
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
