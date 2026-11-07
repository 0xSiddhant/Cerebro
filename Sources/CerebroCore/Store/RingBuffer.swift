/// A fixed-size buffer that drops its oldest element when full.
struct RingBuffer<Element> {
    private var storage: [Element] = []
    private var oldest = 0
    private let capacity: Int

    init(capacity: Int) {
        self.capacity = max(capacity, 1)
    }

    /// The elements, oldest first.
    var elements: [Element] {
        Array(storage[oldest...] + storage[..<oldest])
    }

    mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[oldest] = element
            oldest = (oldest + 1) % capacity
        }
    }
}
