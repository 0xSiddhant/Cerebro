/// A fixed-size buffer that drops its oldest element when full.
struct RingBuffer<Element> {
    private var slots: [Element?] = []
    private var oldest = 0
    private var storedCount = 0
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    /// The elements, oldest first.
    var elements: [Element] {
        (0..<storedCount).compactMap { slots[(oldest + $0) % capacity] }
    }

    /// Adds an element, and returns the one it pushed out, if any.
    @discardableResult
    mutating func append(_ element: Element) -> Element? {
        let evicted = storedCount == capacity ? removeOldest() : nil
        let index = (oldest + storedCount) % capacity
        if index == slots.count {
            slots.append(element)
        } else {
            slots[index] = element
        }
        storedCount += 1
        return evicted
    }

    /// Replaces the newest element that matches, in place, and returns the one it replaced.
    @discardableResult
    mutating func replaceLast(where matches: (Element) -> Bool, with element: Element) -> Element? {
        for offset in (0..<storedCount).reversed() {
            let index = (oldest + offset) % capacity
            if let existing = slots[index], matches(existing) {
                slots[index] = element
                return existing
            }
        }
        return nil
    }

    /// Removes every element.
    mutating func removeAll() {
        slots.removeAll()
        oldest = 0
        storedCount = 0
    }

    /// Removes and returns the oldest element, if there is one.
    @discardableResult
    mutating func removeOldest() -> Element? {
        guard storedCount > 0 else { return nil }
        let element = slots[oldest]
        slots[oldest] = nil
        oldest = (oldest + 1) % capacity
        storedCount -= 1
        return element
    }
}
