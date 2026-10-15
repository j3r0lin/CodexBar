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
    func `windows without a duration keep their position`() {
        let first = self.window(nil, used: 10)
        let second = self.window(nil, used: 40)
        let slots = OverviewCompactAccountRow.slots(
            of: UsageSnapshot(primary: first, secondary: second, updatedAt: Date()))
        #expect(slots.short == first)
        #expect(slots.long == second)
    }

    @Test
    func `a reading above zero is at least a dot and zero has no fill`() {
        #expect(UsageBar.fillWidth(used: 0, barWidth: 100, height: 5) == 0)
        #expect(UsageBar.fillWidth(used: 1, barWidth: 100, height: 5) == 5)
        #expect(UsageBar.fillWidth(used: 50, barWidth: 100, height: 5) == 50)
        #expect(UsageBar.fillWidth(used: 120, barWidth: 100, height: 5) == 100)
    }
}
