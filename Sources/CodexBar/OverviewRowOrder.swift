import Foundation

/// The order of the Overview's account rows, as the user dragged them. Row identifiers name a row
/// across launches, and a row hidden for a while keeps the place it held in the saved order.
enum OverviewRowOrder {
    /// `rows` sorted by the saved order. Rows the saved order does not mention (a new account, a
    /// renamed wire ID) keep their incoming relative order and follow every row it does mention.
    static func ordered<Row>(_ rows: [Row], id: (Row) -> String, saved: [String]) -> [Row] {
        let rank = Dictionary(saved.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return rows.enumerated()
            .sorted { lhs, rhs in
                let lhsRank = rank[id(lhs.element)] ?? saved.count
                let rhsRank = rank[id(rhs.element)] ?? saved.count
                return lhsRank == rhsRank ? lhs.offset < rhs.offset : lhsRank < rhsRank
            }
            .map(\.element)
    }

    /// The order to persist after a drop: every saved slot whose row is on screen now takes the
    /// next row of the new visible order, a slot whose row this menu did not show keeps its
    /// identifier, and visible rows the saved order never saw follow at the end. A hidden account
    /// therefore comes back where it was instead of falling to the bottom.
    static func merged(saved: [String], visible: [String]) -> [String] {
        let visibleIDs = Set(visible)
        var nextVisible = 0
        var merged = saved.map { identifier -> String in
            guard visibleIDs.contains(identifier), nextVisible < visible.count else { return identifier }
            defer { nextVisible += 1 }
            return visible[nextVisible]
        }
        merged.append(contentsOf: visible[nextVisible...])
        return merged
    }
}
