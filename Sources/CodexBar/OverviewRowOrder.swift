import Foundation

/// The order of the Overview's account rows, as the user dragged them. Row identifiers name a row
/// across launches, so an account that is hidden for a while returns to its place.
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

    /// The order to persist after a drop: the rows on screen now in their new order, then the
    /// identifiers the saved order still has but this menu did not show, keeping their old relative
    /// order. Hiding an account therefore does not move it to the end for good.
    static func merged(saved: [String], visible: [String]) -> [String] {
        var seen = Set<String>()
        return (visible + saved).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}
