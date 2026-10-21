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
    func `a pace tick and tint do not change the row height`() {
        let reset = Self.now.addingTimeInterval(3 * 86400)
        func height(pacePercent: Double?, tone: OverviewCompactAccountRow.PaceTone) -> CGFloat {
            self.height(OverviewCompactAccountRow(
                name: "Claude",
                shortWindow: nil,
                longWindow: nil,
                width: Self.width,
                namedLines: [
                    .init(label: "5h", used: 40, resetsAt: reset),
                    .init(label: "7d", used: 60, resetsAt: reset, pacePercent: pacePercent, paceTone: tone),
                ],
                now: Self.now))
        }
        let plain = height(pacePercent: nil, tone: .neutral)
        let paced = height(pacePercent: 50, tone: .runsOut)
        #expect(paced == plain)
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
    func `a reset time is written with a space between its units`() {
        #expect(self.countdown(minutes: 140) == "2h 20m")
        #expect(self.countdown(minutes: 9900) == "6d 21h")
        #expect(self.countdown(minutes: 18) == "18m")
        #expect(self.countdown(minutes: 52) == "52m")
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
