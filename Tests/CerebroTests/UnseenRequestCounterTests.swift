import Foundation
import Testing
@testable import Cerebro

private func requests(_ count: Int) -> [HTTPTransaction] {
    (0..<count).map { _ in
        HTTPTransaction(request: CapturedRequest(url: nil, method: "GET", startDate: Date(timeIntervalSince1970: 0)))
    }
}

@Test func startsAtZero() {
    var counter = UnseenRequestCounter()

    counter.update(with: [])

    #expect(counter.unseenCount == 0)
}

@Test func growsAsRequestsArrive() {
    let all = requests(3)
    var counter = UnseenRequestCounter()

    counter.update(with: Array(all.prefix(1)))
    #expect(counter.unseenCount == 1)

    counter.update(with: all)
    #expect(counter.unseenCount == 3)
}

@Test func resetsWhenSeenAndCountsOnlyWhatComesAfter() {
    let all = requests(5)
    var counter = UnseenRequestCounter()
    counter.update(with: Array(all.prefix(3)))

    counter.markAllSeen()
    #expect(counter.unseenCount == 0)

    counter.update(with: Array(all.prefix(3)))
    #expect(counter.unseenCount == 0)

    counter.update(with: all)
    #expect(counter.unseenCount == 2)
}

@Test func countsEverythingStoredOnceTheLastSeenRequestIsEvicted() {
    let all = requests(6)
    var counter = UnseenRequestCounter()
    counter.update(with: Array(all.prefix(1)))
    counter.markAllSeen()

    counter.update(with: Array(all.suffix(4)))

    #expect(counter.unseenCount == 4)
}
