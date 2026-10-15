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
    func `a row is one line tall even when a window is missing`() {
        let both = self.height(short: Self.window(96, minutes: 140), long: Self.window(15, minutes: 9900))
        let missingShort = self.height(short: nil, long: Self.window(90, minutes: 6960))
        #expect(abs(both - missingShort) < 0.5)
    }

    @Test
    func `a reset time is written without separators`() {
        #expect(self.countdown(minutes: 140) == "2h20m")
        #expect(self.countdown(minutes: 9900) == "6d21h")
        #expect(self.countdown(minutes: 18) == "18m")
        #expect(self.countdown(minutes: 52) == "52m")
    }

    private func countdown(minutes: Int) -> String {
        OverviewCompactAccountRow.countdown(
            to: Self.now.addingTimeInterval(TimeInterval(minutes * 60)),
            now: Self.now)
    }

    private func height(short: RateWindow?, long: RateWindow?) -> CGFloat {
        let row = OverviewCompactAccountRow(
            name: "Codex",
            shortWindow: short,
            longWindow: long,
            width: Self.width,
            now: Self.now)
        return NSHostingController(rootView: row)
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
