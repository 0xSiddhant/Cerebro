import Foundation

/// A JSON value as rows that fold. Built off the main thread when a body is opened, from JSON that's
/// already redacted.
struct JSONTree: Equatable {
    /// One visible line of the tree.
    struct Row: Equatable {
        fileprivate let index: Int
        let key: String?
        let value: String
        let depth: Int
        let canExpand: Bool
        let isExpanded: Bool
    }

    private struct Node: Equatable {
        let key: String?
        let value: String
        let depth: Int

        /// The position just past this node's last descendant, so a folded node can be skipped at once.
        var end: Int
    }

    /// Objects and arrays deeper than this start folded, so a large body opens as a short outline.
    private static let initialExpandedDepth = 2

    /// A table cell lays out all of its text on the main thread, so long strings are cut short here. Pretty
    /// and Raw still show them in full.
    private static let rowTextLimit = 500

    private let nodes: [Node]
    private var folded: Set<Int>

    /// What's visible, top to bottom.
    private(set) var rows: [Row] = []

    /// Parses JSON, or returns `nil` if the bytes aren't JSON.
    init?(json: Data) {
        guard let value = try? JSONSerialization.jsonObject(with: json, options: .fragmentsAllowed) else {
            return nil
        }
        var nodes: [Node] = []
        Self.append(value, key: nil, depth: 0, to: &nodes)
        self.nodes = nodes
        folded = Set(
            nodes.indices.filter { nodes[$0].end > $0 + 1 && nodes[$0].depth >= Self.initialExpandedDepth }
        )
        rows = visibleRows()
    }

    /// Folds or unfolds a row, if it has anything to fold.
    mutating func toggle(rowAt position: Int) {
        guard rows.indices.contains(position), rows[position].canExpand else { return }
        let index = rows[position].index
        if folded.remove(index) == nil {
            folded.insert(index)
        }
        rows = visibleRows()
    }

    private func visibleRows() -> [Row] {
        var rows: [Row] = []
        var index = 0
        while index < nodes.count {
            let node = nodes[index]
            let isFolded = folded.contains(index)
            rows.append(
                Row(
                    index: index,
                    key: node.key,
                    value: node.value,
                    depth: node.depth,
                    canExpand: node.end > index + 1,
                    isExpanded: !isFolded
                )
            )
            index = isFolded ? node.end : index + 1
        }
        return rows
    }

    private static func append(_ value: Any, key: String?, depth: Int, to nodes: inout [Node]) {
        let index = nodes.count
        nodes.append(Node(key: key.map(clipped), value: summary(of: value), depth: depth, end: index + 1))
        if let object = value as? [String: Any] {
            for (name, child) in object.sorted(by: { $0.key < $1.key }) {
                append(child, key: name, depth: depth + 1, to: &nodes)
            }
        } else if let array = value as? [Any] {
            for (position, child) in array.enumerated() {
                append(child, key: String(position), depth: depth + 1, to: &nodes)
            }
        }
        nodes[index].end = nodes.count
    }

    private static func clipped(_ text: String) -> String {
        let start = text.prefix(rowTextLimit)
        return start.endIndex == text.endIndex ? text : start + "…"
    }

    private static func summary(of value: Any) -> String {
        switch value {
        case let object as [String: Any]: return "{\(object.count)}"
        case let array as [Any]: return "[\(array.count)]"
        case let text as String: return "\"\(clipped(text))\""
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID()
                ? (number.boolValue ? "true" : "false") : number.stringValue
        default: return "null"
        }
    }
}
