import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct OverviewCompactAccountRowTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let width: CGFloat = 310

    @Test
    func `a row has one line per reported window, short window first`() {
        let both = self.row(short: Self.window(96, minutes: 140), long: Self.window(15, minutes: 9900))
        let missingShort = self.row(short: nil, long: Self.window(90, minutes: 6960))
        #expect(both.lines.map(\.used) == [96, 15])
        #expect(missingShort.lines.map(\.used) == [90])
        #expect(self.height(both) > self.height(missingShort) + 10)
    }

    @Test
    func `a long name wraps to a second line and grows a single-window row`() {
        func height(_ name: String) -> CGFloat {
            self.height(OverviewCompactAccountRow(
                name: name,
                shortWindow: nil,
                longWindow: Self.window(40, minutes: 300),
                width: Self.width,
                namesProvider: true,
                now: Self.now))
        }
        #expect(height("Some Very Long Provider Name That Cannot Fit In One Header Line") > height("Codex"))
    }

    @Test
    func `the header shows an update label only when a timestamp exists`() {
        var row = self.row(short: nil, long: Self.window(40, minutes: 300))
        #expect(row.updatedText == nil)
        row.updatedAt = Self.now.addingTimeInterval(-180)
        #expect(row.updatedText?.isEmpty == false)
        row.updatedAt = nil
        #expect(row.updatedText == nil)
    }

    @Test
    func `update labels use the timestamp belonging to the row source`() {
        let readAt = Self.now.addingTimeInterval(-180)
        let snapshot = UsageSnapshot(primary: nil, secondary: nil, updatedAt: Self.now)
        func row(magpie: Bool, snapshot: UsageSnapshot?, readAt: Date?) -> OverviewUsageRow {
            OverviewUsageRow(
                groupKey: "example",
                providerName: "Example",
                nativeProvider: nil,
                accountID: nil,
                accountName: nil,
                namedWindows: magpie ? [] : nil,
                snapshot: snapshot,
                model: nil,
                errorText: nil,
                showsErrorFlag: false,
                detailErrorText: nil,
                readAt: readAt)
        }
        #expect(row(magpie: true, snapshot: nil, readAt: readAt).updatedAt == readAt)
        #expect(row(magpie: false, snapshot: snapshot, readAt: nil).updatedAt == snapshot.updatedAt)
        #expect(row(magpie: true, snapshot: nil, readAt: nil).updatedAt == nil)
        #expect(row(magpie: false, snapshot: nil, readAt: nil).updatedAt == nil)
    }

    @Test
    func `a reset shows both a countdown and an absolute time only when one exists`() {
        let resetAt = Self.now.addingTimeInterval(4 * 3600 + 22 * 60)
        let withReset = OverviewCompactAccountRow.Line(label: "5h", used: 40, resetsAt: resetAt)
        let shown = OverviewCompactAccountRow.resetText(withReset, now: Self.now)
        let countdown = OverviewCompactAccountRow.countdown(to: resetAt, now: Self.now)
        let absolute = OverviewCompactAccountRow.shortClock(resetAt, now: Self.now)
        #expect(shown.contains(countdown))
        #expect(shown.contains(absolute))
        let withoutReset = OverviewCompactAccountRow.Line(label: "5h", used: 0, resetsAt: nil)
        let absent = OverviewCompactAccountRow.resetText(withoutReset, now: Self.now)
        #expect(absent.allSatisfy { !$0.isNumber })
    }

    @Test
    func `a reset time is written with a space between its units`() {
        #expect(self.countdown(minutes: 140) == "2h 20m")
        #expect(self.countdown(minutes: 9900) == "6d 21h")
        #expect(self.countdown(minutes: 18) == "18m")
        #expect(self.countdown(minutes: 52) == "52m")
    }

    @Test
    func `a hidden usage item takes its window off the row`() {
        let snapshot = UsageSnapshot(
            primary: Self.window(40, minutes: 300),
            secondary: Self.window(70, minutes: 10080),
            updatedAt: Self.now)
        let both = OverviewCompactAccountRow.slots(of: snapshot)
        #expect(both.short != nil)
        #expect(both.long != nil)

        let sessionHidden = OverviewCompactAccountRow.slots(
            of: snapshot,
            hiddenItemIDs: [.metric("primary")])
        #expect(sessionHidden.short == nil)
        #expect(sessionHidden.long?.usedPercent == 70)

        let weeklyHidden = OverviewCompactAccountRow.slots(
            of: snapshot,
            hiddenItemIDs: [.metric("secondary")])
        #expect(weeklyHidden.short?.usedPercent == 40)
        #expect(weeklyHidden.long == nil)

        let allHidden = OverviewCompactAccountRow.slots(
            of: snapshot,
            hiddenItemIDs: [.metric("primary"), .metric("secondary")])
        #expect(allHidden.short == nil)
        #expect(allHidden.long == nil)
    }

    @Test
    func `showing remaining flips the number and the fill but not the severity colour`() {
        let line = OverviewCompactAccountRow.Line(
            label: "7d",
            used: 60,
            resetsAt: nil,
            warningWindow: .weekly)
        let thresholds = (session: [50, 20], weekly: [50, 20])
        let usedReading = self.reading(line, showsRemaining: false, thresholds: thresholds)
        let remainingReading = self.reading(line, showsRemaining: true, thresholds: thresholds)
        #expect(usedReading.percent == 60)
        #expect(remainingReading.percent == 40)
        #expect(usedReading.barColor == remainingReading.barColor)
        #expect(usedReading.percentColor == remainingReading.percentColor)
        #expect(usedReading.barColor == OverviewPalette.warning)
    }

    @Test
    func `warning thresholds colour the reading on the used scale of each window`() {
        let thresholds = (session: [50, 20], weekly: [50, 20])
        // Remaining 50 and 20 become 50% and 80% used.
        #expect(self.reading(self.line(used: 30), thresholds: thresholds).barColor == OverviewPalette.accent)
        #expect(self.reading(self.line(used: 50), thresholds: thresholds).barColor == OverviewPalette.warning)
        #expect(self.reading(self.line(used: 80, window: .weekly), thresholds: thresholds).barColor ==
            OverviewPalette.critical)
        // Disabled thresholds keep the 70/90 fallback.
        let disabled = (session: [0], weekly: [0])
        #expect(self.reading(self.line(used: 60, window: .weekly), thresholds: disabled).barColor ==
            OverviewPalette.accent)
        #expect(self.reading(self.line(used: 75, window: .weekly), thresholds: disabled).barColor ==
            OverviewPalette.warning)
        #expect(self.reading(self.line(used: 92, window: .weekly), thresholds: disabled).barColor ==
            OverviewPalette.critical)
    }

    @Test
    func `each window kind uses its own thresholds`() {
        let thresholds = (session: [50, 20], weekly: [0])
        #expect(self.reading(self.line(used: 60), thresholds: thresholds).barColor == OverviewPalette.warning)
        #expect(self.reading(self.line(used: 60, window: .weekly), thresholds: thresholds).barColor ==
            OverviewPalette.accent)
    }

    @Test
    func `hiding pace drops the tick and the hatching`() {
        let line = OverviewCompactAccountRow.Line(label: "7d", used: 80, resetsAt: nil, pacePercent: 70)
        let withPace = self.reading(line)
        #expect(withPace.pacePercent == 70)
        #expect(withPace.overruns)

        let withoutPace = self.reading(line, showsPace: false)
        #expect(withoutPace.pacePercent == nil)
        #expect(!withoutPace.overruns)
    }

    @Test
    func `the percent is white until it reaches a warning threshold`() {
        let thresholds = (session: [50, 20], weekly: [50, 20])
        // Pace never tints the number; only the thresholds do.
        let ahead = OverviewCompactAccountRow.Line(label: "5h", used: 30, resetsAt: nil, pacePercent: 10)
        #expect(self.reading(ahead, thresholds: thresholds).percentColor == OverviewPalette.text)
        #expect(self.reading(self.line(used: 0), thresholds: thresholds).percentColor == OverviewPalette.text)
        #expect(self.reading(self.line(used: 50), thresholds: thresholds).percentColor == OverviewPalette.warning)
        #expect(self.reading(self.line(used: 80), thresholds: thresholds).percentColor == OverviewPalette.critical)
        // The bar stays on the accent colour in the normal range.
        #expect(self.reading(self.line(used: 30), thresholds: thresholds).barColor == OverviewPalette.accent)
    }

    @Test
    func `the provider name shows beside an account name unless it is the name`() {
        #expect(StatusItemController.providerTag(providerName: "Claude", displayedName: "claude-1") == "Claude")
        #expect(StatusItemController.providerTag(providerName: "Droid", displayedName: "work") == "Droid")
        #expect(StatusItemController.providerTag(providerName: "Codex", displayedName: "codex") == nil)
        #expect(StatusItemController.providerTag(providerName: "OpenCode Go", displayedName: "OpenCode Go") == nil)
    }

    @Test
    func `a remaining display mirrors the pace tick onto the leftover side of the bar`() {
        #expect(self.reading(self.line(used: 40, pace: 70), showsRemaining: true).pacePercent == 30)
        #expect(self.reading(self.line(used: 90, pace: 10), showsRemaining: true).pacePercent == 90)
    }

    @Test
    func `only usage ahead of visible pace draws an overrun segment`() {
        #expect(self.overrun(self.line(used: 70, pace: 50))?.start == 50)
        #expect(self.overrun(self.line(used: 70, pace: 50))?.end == 70)
        #expect(self.overrun(self.line(used: 50, pace: 50)) == nil)
        #expect(self.overrun(self.line(used: 30, pace: 50)) == nil)
        #expect(self.overrun(self.line(used: 70)) == nil)
        #expect(self.overrun(self.line(used: 70, pace: 50), showsPace: false) == nil)
    }

    @Test
    func `overrun follows the display direction`() {
        let line = OverviewCompactAccountRow.Line(label: "7d", used: 70, resetsAt: nil, pacePercent: 50)
        let segment = self.overrun(line, showsRemaining: true)
        #expect(segment?.start == 30)
        #expect(segment?.end == 50)
        #expect(self.overrun(self.line(used: 30, pace: 50), showsRemaining: true) == nil)
    }

    @Test
    func `overrun stays within the track and omits subpercent spans`() {
        let segment = self.overrun(self.line(used: 110, pace: -10))
        #expect(segment?.start == 0)
        #expect(segment?.end == 100)
        #expect(self.overrun(self.line(used: 50.5, pace: 50)) == nil)
        #expect(self.overrun(self.line(used: 51, pace: 50))?.end == 51)
    }

    @Test
    func `a remaining display hatches the gap on the track, not the fill`() {
        // 70% used with the tick at 50%: the fill is the 30% left, so the 30...50 gap lies outside it.
        let remaining = self.bar(self.line(used: 70, pace: 50), showsRemaining: true)
        #expect(remaining.overrunSegment?.start == 30)
        #expect(remaining.overrunSegment?.end == 50)
        #expect(!remaining.overrunIsInsideFill)
        // Used display: the usage past the tick lies on the fill.
        let used = self.bar(self.line(used: 70, pace: 50), showsRemaining: false)
        #expect(used.overrunSegment?.start == 50)
        #expect(used.overrunSegment?.end == 70)
        #expect(used.overrunIsInsideFill)
    }

    private func bar(_ line: OverviewCompactAccountRow.Line, showsRemaining: Bool) -> UsageBar {
        let reading = self.reading(line, showsRemaining: showsRemaining)
        return UsageBar(
            used: reading.percent,
            color: reading.barColor,
            trackColor: OverviewCompactAccountRow.trackColor,
            height: OverviewCompactAccountRow.barHeight,
            pacePercent: reading.pacePercent,
            overruns: reading.overruns)
    }

    private func overrun(
        _ line: OverviewCompactAccountRow.Line,
        showsRemaining: Bool = false,
        showsPace: Bool = true) -> (start: Double, end: Double)?
    {
        let reading = self.reading(line, showsRemaining: showsRemaining, showsPace: showsPace)
        return UsageBar(
            used: reading.percent,
            color: reading.barColor,
            trackColor: OverviewCompactAccountRow.trackColor,
            height: OverviewCompactAccountRow.barHeight,
            pacePercent: reading.pacePercent,
            overruns: reading.overruns).overrunSegment
    }

    private func reading(
        _ line: OverviewCompactAccountRow.Line,
        showsRemaining: Bool = false,
        showsPace: Bool = true,
        thresholds: (session: [Int]?, weekly: [Int]?) = (nil, nil))
        -> OverviewCompactAccountRow.Reading
    {
        OverviewCompactAccountRow(
            name: "Codex",
            shortWindow: nil,
            longWindow: nil,
            width: Self.width,
            display: OverviewDisplayOptions(
                showsRemaining: showsRemaining,
                sessionWarningThresholds: thresholds.session,
                weeklyWarningThresholds: thresholds.weekly,
                showsPace: showsPace),
            now: Self.now)
            .reading(for: line)
    }

    private func line(
        used: Double,
        window: QuotaWarningWindow = .session,
        pace: Double? = nil) -> OverviewCompactAccountRow.Line
    {
        OverviewCompactAccountRow.Line(
            label: "5h",
            used: used,
            resetsAt: nil,
            warningWindow: window,
            pacePercent: pace)
    }

    private func countdown(minutes: Int) -> String {
        OverviewCompactAccountRow.countdown(
            to: Self.now.addingTimeInterval(TimeInterval(minutes * 60)),
            now: Self.now)
    }

    private func row(short: RateWindow?, long: RateWindow?) -> OverviewCompactAccountRow {
        OverviewCompactAccountRow(
            name: "Codex",
            shortWindow: short,
            longWindow: long,
            width: Self.width,
            now: Self.now)
    }

    private func height(_ row: OverviewCompactAccountRow) -> CGFloat {
        NSHostingController(rootView: row)
            .sizeThatFits(in: CGSize(width: Self.width, height: .greatestFiniteMagnitude))
            .height
    }

    private static func window(_ usedPercent: Double, minutes: Int) -> RateWindow {
        RateWindow(
            usedPercent: usedPercent,
            windowMinutes: minutes,
            resetsAt: self.now.addingTimeInterval(TimeInterval(minutes * 60)),
            resetDescription: nil)
    }
}
