import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

/// The Overview rows share one column grid: every row draws a window's bar in the same x range for its
/// column, so the list reads as columns.
@MainActor
struct OverviewRowAlignmentTests {
    private static let width = StatusItemController.overviewMenuMinimumWidth
    private static let scale: CGFloat = 2
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Scenario {
        let name: String
        let provider: Bool
        /// The windows' labels with the column each prefers.
        let windows: [(label: String, column: OverviewColumn)]
    }

    private static let scenarios = [
        Scenario(name: "Codex", provider: true, windows: [("5h", .session), ("7d", .weekly)]),
        Scenario(name: "claude-1", provider: false, windows: [("5h", .session), ("7d", .weekly), ("Fable", .other)]),
        Scenario(name: "Kimi Code", provider: true, windows: [("5h", .session), ("7d", .weekly), ("30d", .other)]),
        Scenario(name: "Grok", provider: true, windows: [("7d", .weekly)]),
        Scenario(name: "Cursor", provider: true, windows: [("30d", .other)]),
    ]

    /// At the 400pt menu width the name column takes 104pt after the 20pt inset, and the cells split the
    /// remaining 226pt after three 10pt gaps.
    private static let cellStarts: [CGFloat] = [134, 219.3333, 304.6667]
    private static let cellWidth: CGFloat = 75.3333

    @Test
    func `a window's bar ends on its column's right edge and a tagless bar starts on its left edge`() throws {
        #expect(Self.width == 400)
        for scenario in Self.scenarios {
            let spans = try Self.barSpans(in: Self.render(Self.row(scenario)))
            for window in scenario.windows {
                let start = Int(Self.cellStarts[window.column.rawValue] * Self.scale)
                let end = Int((Self.cellStarts[window.column.rawValue] + Self.cellWidth) * Self.scale)
                let named = window.label != window.column.head
                #expect(
                    spans.contains { abs($0.end - end) <= 2 && (named || abs($0.start - start) <= 2) },
                    "\(scenario.name) \(window.label): no bar \(start)...\(end) in \(spans)")
            }
        }
    }

    @Test
    func `a day-count window name with no duration gets the compact label`() {
        func label(_ name: String) -> String {
            OverviewUsageRow.NamedWindow(window: MagpieQuotaWindow(name: name, usedPercent: 1, resetsAt: nil)).label
        }
        #expect(label("30 days") == "30d")
        #expect(label("12 hours") == "12h")
        #expect(label("Credits") == "Credits")
    }

    // MARK: - Rendering and measuring

    private static func lines(_ scenario: Scenario) -> [OverviewCompactAccountRow.Line] {
        scenario.windows.map { window in
            OverviewCompactAccountRow.Line(
                label: window.label,
                used: 40,
                resetsAt: self.now.addingTimeInterval(window.label == "30d" ? 26 * 86400 + 13 * 3600 : 3 * 86400),
                column: window.column,
                pacePercent: window.label == "7d" ? 50 : nil)
        }
    }

    private static func row(_ scenario: Scenario) -> some View {
        let lines = self.lines(scenario)
        return OverviewCompactAccountRow(
            name: scenario.name,
            shortWindow: nil,
            longWindow: nil,
            width: self.width,
            namesProvider: scenario.provider,
            namedLines: lines,
            now: self.now)
            .background(Color(red: 0.14, green: 0.14, blue: 0.16))
            .environment(\.colorScheme, .dark)
    }

    private static func render(_ view: some View) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view)
        renderer.scale = self.scale
        return try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
    }

    private struct Span: Hashable, CustomStringConvertible {
        let start: Int
        let end: Int
        var description: String {
            "\(self.start)...\(self.end)"
        }
    }

    /// Scan past the name column to measure the usage bars.
    private static var scanStart: Int {
        let nameEnd = OverviewCompactAccountRow.contentInset + OverviewCompactAccountRow.nameWidth
        return Int((nameEnd + OverviewCompactAccountRow.columnSpacing) * self.scale)
    }

    private static func differs(_ a: NSColor, _ b: NSColor) -> Bool {
        abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent)
            + abs(a.blueComponent - b.blueComponent) > 0.12
    }

    /// Horizontal runs of 36px or more that differ from the card background are bars: text glyphs break
    /// into short runs. Every pixel row of one bar reports the same span, so a Set holds one per bar.
    private static func barSpans(in image: NSBitmapImageRep) -> Set<Span> {
        var spans = Set<Span>()
        let from = self.scanStart
        for y in self.interiorRows(of: image) {
            guard let reference = image.colorAt(x: self.referenceX, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            var runStart: Int?
            for x in from..<image.pixelsWide {
                let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)
                let ink = color.map { self.differs($0, reference) } ?? false
                if ink, runStart == nil { runStart = x }
                if !ink || x == image.pixelsWide - 1, let start = runStart {
                    if x - start >= 36 { spans.insert(Span(start: start, end: x)) }
                    runStart = nil
                }
            }
        }
        return spans
    }

    /// Background sample column: left of any content.
    private static var referenceX: Int {
        Int((OverviewCompactAccountRow.contentInset - 6) * self.scale)
    }

    /// Rows clear of the row's vertical padding and the divider hairline at its bottom.
    private static func interiorRows(of image: NSBitmapImageRep) -> Range<Int> {
        let margin = Int(OverviewCompactAccountRow.verticalPadding * self.scale)
        return margin..<max(margin, image.pixelsHigh - margin)
    }
}
