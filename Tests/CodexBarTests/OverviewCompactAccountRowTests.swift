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
    func `a pace phrase under the reset countdown does not make the row taller`() {
        let reset = Self.now.addingTimeInterval(3 * 86400)
        func height(paceText: String?) -> CGFloat {
            self.height(OverviewCompactAccountRow(
                name: "Claude",
                shortWindow: nil,
                longWindow: nil,
                width: Self.width,
                namedLines: [
                    .init(label: "5h", used: 40, resetsAt: reset),
                    .init(label: "7d", used: 60, resetsAt: reset, paceText: paceText),
                ],
                now: Self.now))
        }
        let plain = height(paceText: nil)
        let paced = height(paceText: "Runs out in 1d 4h")
        #expect(paced == plain)
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
