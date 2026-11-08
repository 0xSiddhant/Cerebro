import Testing
@testable import CerebroCore

@Test func bufferKeepsEverythingUpToItsCapacity() {
    var buffer = RingBuffer<Int>(capacity: 3)
    buffer.append(1)
    buffer.append(2)

    #expect(buffer.elements == [1, 2])
}

@Test func bufferDropsTheOldestFirst() {
    var buffer = RingBuffer<Int>(capacity: 3)
    (1...5).forEach { buffer.append($0) }

    #expect(buffer.elements == [3, 4, 5])
}

@Test func bufferStaysInOrderAcrossManyWraps() {
    var buffer = RingBuffer<Int>(capacity: 4)
    (1...1_003).forEach { buffer.append($0) }

    #expect(buffer.elements == [1_000, 1_001, 1_002, 1_003])
}
