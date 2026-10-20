import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

/// The Overview rows share one column grid: a lone provider card and an account row inside a group draw
/// their bars over the same x range, so the list reads as columns.
@MainActor
struct OverviewRowAlignmentTests {
    private static let width = StatusItemController.overviewMenuMinimumWidth
    private static let scale: CGFloat = 2
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private struct Scenario {
        let name: String
        let provider: Bool
        let labels: [String]
    }

    private static let scenarios = [
        Scenario(name: "Codex", provider: true, labels: ["5h", "7d"]),
        Scenario(name: "OpenCode Go", provider: true, labels: ["5h", "7d"]),
        Scenario(name: "claude-1", provider: false, labels: ["5h", "7d", "Fable"]),
        Scenario(name: "Kimi Code", provider: true, labels: ["5h", "7d", "30d"]),
        Scenario(name: "Grok", provider: true, labels: ["7d"]),
    ]

    @Test
    func `bars start and end at the same x on lone provider rows and account rows`() throws {
        var report: [String] = []
        var spans: [Set<Span>] = []
        for scenario in Self.scenarios {
            let image = try Self.render(Self.row(scenario))
            let found = Self.barSpans(in: image)
            spans.append(found)
            let sorted = found.sorted { $0.start < $1.start }
            report.append(
                "\(scenario.name): name ink x=\(Self.nameInkStart(in: image)) "
                    + "bar extent=\(Self.extent(found)) spans=\(sorted)")
        }
        if let dir = ProcessInfo.processInfo.environment["CODEXBAR_ROW_ALIGN_DIR"] {
            try report.joined(separator: "\n").write(
                toFile: URL(fileURLWithPath: dir).appendingPathComponent("measurements.txt").path,
                atomically: true,
                encoding: .utf8)
            let composite = VStack(alignment: .leading, spacing: 0) {
                ForEach(Self.scenarios.indices, id: \.self) { Self.row(Self.scenarios[$0]) }
            }
            .padding(.vertical, 6)
            .background(Color(red: 0.14, green: 0.14, blue: 0.16))
            .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: composite)
            renderer.scale = Self.scale
            let bitmap = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: URL(fileURLWithPath: dir).appendingPathComponent("composite.png"))
        }
        // Capsule ends antialias differently on each pixel row, so compare the outermost extent of the bars.
        let extents = spans.map(Self.extent)
        let first = try #require(extents.first)
        #expect(first.start >= 0, "no bar found in the first row")
        for (index, extent) in extents.enumerated() {
            #expect(
                extent == first,
                "\(Self.scenarios[index].name) bar extent \(extent) != \(first): \(report)")
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

    private static func row(_ scenario: Scenario) -> some View {
        let lines = scenario.labels.map { label in
            OverviewCompactAccountRow.Line(
                label: label,
                used: 40,
                resetsAt: self.now.addingTimeInterval(label == "30d" ? 26 * 86400 + 13 * 3600 : 3 * 86400),
                pacePercent: label == "7d" ? 50 : nil)
        }
        return OverviewCompactAccountRow(
            name: scenario.name,
            shortWindow: nil,
            longWindow: nil,
            width: self.width,
            namesProvider: scenario.provider,
            namedLines: lines,
            showsDetailChevron: scenario.provider,
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

    private static func extent(_ spans: Set<Span>) -> Span {
        Span(start: spans.map(\.start).min() ?? -1, end: spans.map(\.end).max() ?? -1)
    }

    /// Scan past the shared name column so names and icons never count as bars.
    private static var scanStart: Int {
        let contentInset = OverviewCompactAccountRow.blockInset + OverviewCompactAccountRow.horizontalPadding
        return Int((contentInset + OverviewCompactAccountRow.nameColumn) * self.scale)
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

    /// Card background sample column: right of the card border and its corner arcs, left of any content.
    private static var referenceX: Int {
        Int((OverviewCompactAccountRow.blockInset + 6) * self.scale)
    }

    /// Rows clear of the card's top and bottom border lines and corner arcs; the image also holds the
    /// transparent gap below the card.
    private static func interiorRows(of image: NSBitmapImageRep) -> Range<Int> {
        let margin = Int(8 * self.scale)
        let bottom = image.pixelsHigh - Int(OverviewCompactAccountRow.blockGap * self.scale) - margin
        return margin..<max(margin, bottom)
    }

    /// Leftmost inked pixel of the name area: the icon on a provider row, the first glyph on an account row.
    private static func nameInkStart(in image: NSBitmapImageRep) -> Int {
        let from = Int((OverviewCompactAccountRow.blockInset + 8) * self.scale)
        for x in from..<self.scanStart {
            for y in self.interiorRows(of: image) {
                guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                      let reference = image.colorAt(x: self.referenceX, y: y)?.usingColorSpace(.deviceRGB)
                else { continue }
                if self.differs(color, reference) { return x }
            }
        }
        return -1
    }
}
