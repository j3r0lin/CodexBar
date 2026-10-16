import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct OverviewWindowSlotTests {
    private func window(_ minutes: Int?, used: Double) -> RateWindow {
        RateWindow(usedPercent: used, windowMinutes: minutes, resetsAt: nil, resetDescription: nil)
    }

    @Test
    func `a lone seven day window fills the long slot and leaves the short slot empty`() {
        let weekly = self.window(7 * 1440, used: 30)
        let slots = OverviewCompactAccountRow.slots(
            of: UsageSnapshot(primary: weekly, secondary: nil, updatedAt: Date()))
        #expect(slots.short == nil)
        #expect(slots.long == weekly)
    }

    @Test
    func `windows are placed by duration regardless of position`() {
        let session = self.window(300, used: 10)
        let weekly = self.window(7 * 1440, used: 40)
        let slots = OverviewCompactAccountRow.slots(
            of: UsageSnapshot(primary: weekly, secondary: session, updatedAt: Date()))
        #expect(slots.short == session)
        #expect(slots.long == weekly)
    }

    @Test
    func `untyped windows reserve neutral slots without implying a short period`() {
        let first = self.window(nil, used: 10)
        let second = self.window(nil, used: 40)
        let slots = OverviewCompactAccountRow.slots(
            of: UsageSnapshot(primary: first, secondary: second, updatedAt: Date()))
        #expect(slots.short == second)
        #expect(slots.long == first)
    }

    @Test
    func `a native Grok untyped credit pool keeps its weekly label`() {
        let weekly = RateWindow(
            usedPercent: 30,
            windowMinutes: nil,
            resetsAt: Date().addingTimeInterval(3600),
            resetDescription: "Localized reset prose")
        let slots = OverviewCompactAccountRow.slots(
            of: UsageSnapshot(primary: weekly, secondary: nil, updatedAt: Date()), provider: .grok)
        let row = OverviewCompactAccountRow(
            name: "Grok",
            shortWindow: slots.short,
            longWindow: slots.long,
            width: 340,
            provider: .grok)
        #expect(slots.short == nil)
        #expect(row.lines.map(\.label) == ["7d"])
    }

    @Test
    func `an unknown untyped window never claims a five hour period`() {
        let reading = RateWindow(
            usedPercent: 30, windowMinutes: nil, resetsAt: nil, resetDescription: "7 days")
        let slots = OverviewCompactAccountRow.slots(
            of: UsageSnapshot(primary: reading, secondary: nil, updatedAt: Date()))
        let row = OverviewCompactAccountRow(
            name: "Provider", shortWindow: slots.short, longWindow: slots.long, width: 340)
        #expect(slots.short == nil)
        #expect(row.lines.count == 1)
        #expect(row.lines.first?.label == "—")
    }

    @Test
    func `a reading above zero is at least a dot and zero has no fill`() {
        #expect(UsageBar.fillWidth(used: 0, barWidth: 100, height: 5) == 0)
        #expect(UsageBar.fillWidth(used: 1, barWidth: 100, height: 5) == 5)
        #expect(UsageBar.fillWidth(used: 50, barWidth: 100, height: 5) == 50)
        #expect(UsageBar.fillWidth(used: 120, barWidth: 100, height: 5) == 100)
    }
}
