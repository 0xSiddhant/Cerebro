import Foundation

#if SWIFT_PACKAGE
import CerebroCore
#endif

/// Counts the requests captured since the dashboard was last opened, for the floating trigger's badge.
struct UnseenRequestCounter {
    private(set) var unseenCount = 0
    private var newestID: UUID?
    private var lastSeenID: UUID?

    /// Takes the store's transactions, oldest first. If the last seen one has been evicted, every
    /// stored request counts as unseen.
    mutating func update(with transactions: [HTTPTransaction]) {
        newestID = transactions.last?.id
        unseenCount = transactions.reversed().prefix { $0.id != lastSeenID }.count
    }

    mutating func markAllSeen() {
        lastSeenID = newestID
        unseenCount = 0
    }
}
