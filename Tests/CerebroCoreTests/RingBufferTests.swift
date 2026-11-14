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

@Test func appendReturnsWhatItPushedOut() {
    var buffer = RingBuffer<Int>(capacity: 2)

    #expect(buffer.append(1) == nil)
    #expect(buffer.append(2) == nil)
    #expect(buffer.append(3) == 1)
    #expect(buffer.elements == [2, 3])
}

@Test func removeOldestTakesFromTheFront() {
    var buffer = RingBuffer<Int>(capacity: 3)
    buffer.append(1)
    buffer.append(2)

    #expect(buffer.removeOldest() == 1)
    #expect(buffer.elements == [2])
}

@Test func removeOldestOnAnEmptyBufferIsNil() {
    var buffer = RingBuffer<Int>(capacity: 1)

    #expect(buffer.removeOldest() == nil)
}

@Test func keepsOrderWhenAppendsAndRemovalsMixAcrossTheEnd() {
    var buffer = RingBuffer<Int>(capacity: 3)
    buffer.append(1)
    buffer.append(2)
    buffer.append(3)
    buffer.removeOldest()
    buffer.removeOldest()

    #expect(buffer.append(4) == nil)
    #expect(buffer.append(5) == nil)
    #expect(buffer.elements == [3, 4, 5])
    #expect(buffer.append(6) == 3)
    #expect(buffer.elements == [4, 5, 6])
}
