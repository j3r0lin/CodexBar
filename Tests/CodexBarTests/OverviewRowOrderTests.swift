import Testing
@testable import CodexBar

/// The Overview's account rows follow the order the user dragged them into, even while some rows
/// are missing from the menu.
struct OverviewRowOrderTests {
    private struct Row {
        let id: String
    }

    @Test
    func `rows follow the saved order and unlisted rows keep their relative order after it`() {
        let rows = ["c", "a", "d", "b"].map { Row(id: $0) }
        let ordered = OverviewRowOrder.ordered(rows, id: \.id, saved: ["b", "a"])
        #expect(ordered.map(\.id) == ["b", "a", "c", "d"])
    }

    @Test
    func `a saved order naming no current row leaves the list untouched`() {
        let rows = ["c", "a", "d"].map { Row(id: $0) }
        let ordered = OverviewRowOrder.ordered(rows, id: \.id, saved: ["gone"])
        #expect(ordered.map(\.id) == ["c", "a", "d"])
    }

    @Test
    func `a hidden row keeps its saved slot while visible rows move around it`() {
        let saved = ["a", "b", "c"]
        let visible = ["c", "a"]
        #expect(OverviewRowOrder.merged(saved: saved, visible: visible) == ["c", "b", "a"])
    }

    @Test
    func `visible rows fill their saved slots in the order they were dragged`() {
        let saved = ["b", "a", "d", "c"]
        let visible = ["c", "b"]
        #expect(OverviewRowOrder.merged(saved: saved, visible: visible) == ["c", "a", "d", "b"])
    }
}
