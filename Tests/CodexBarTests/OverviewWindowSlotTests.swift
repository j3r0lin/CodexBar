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
    func `a magpie sourced Grok window takes its period label from the Grok descriptor`() throws {
        let accounts = MagpieAccountProjection.snapshots(from: [
            MagpieQuotaRow(
                provider: "grok-plugin",
                email: "",
                organization: "",
                alias: nil,
                isLast: false,
                readAt: nil,
                windows: [
                    MagpieQuotaWindow(
                        name: "7 days",
                        usedPercent: 93,
                        resetsAt: Date().addingTimeInterval(3 * 86400 + 4 * 3600)),
                ],
                error: nil),
        ])
        let account = try #require(accounts.first)
        let snapshot = try #require(MagpieUsageProjection.usageSnapshot(for: account))
        let slots = OverviewCompactAccountRow.slots(of: snapshot, provider: .grok)
        let row = OverviewCompactAccountRow(
            name: "Grok",
            shortWindow: slots.short,
            longWindow: slots.long,
            width: 340,
            provider: .grok)
        #expect(row.lines.map(\.label) == ["7d"])
    }

    @Test
    func `a magpie sourced Grok window whose period is unknown shows a dash`() throws {
        let accounts = MagpieAccountProjection.snapshots(from: [
            MagpieQuotaRow(
                provider: "grok-plugin",
                email: "",
                organization: "",
                alias: nil,
                isLast: false,
                readAt: nil,
                windows: [MagpieQuotaWindow(name: "Month", usedPercent: 40, resetsAt: nil)],
                error: nil),
        ])
        let account = try #require(accounts.first)
        let snapshot = try #require(MagpieUsageProjection.usageSnapshot(for: account))
        let slots = OverviewCompactAccountRow.slots(of: snapshot, provider: .grok)
        let row = OverviewCompactAccountRow(
            name: "Grok",
            shortWindow: slots.short,
            longWindow: slots.long,
            width: 340,
            provider: .grok,
            infersPeriodFromReset: false)
        #expect(row.lines.map(\.label) == ["—"])
    }

    @Test
    func `a magpie sourced Grok window never infers a period from its reset time`() throws {
        let accounts = MagpieAccountProjection.snapshots(from: [
            MagpieQuotaRow(
                provider: "grok-plugin",
                email: "",
                organization: "",
                alias: nil,
                isLast: false,
                readAt: nil,
                windows: [
                    MagpieQuotaWindow(
                        name: "Month",
                        usedPercent: 40,
                        resetsAt: Date().addingTimeInterval(5 * 86400)),
                ],
                error: nil),
        ])
        let account = try #require(accounts.first)
        let snapshot = try #require(MagpieUsageProjection.usageSnapshot(for: account))
        // A native Grok window with the same shape would title "Weekly" from the reset distance;
        // the magpie-sourced one keeps its period unknown.
        #expect(GrokProviderDescriptor.displayLabel(window: snapshot.primary) == "Weekly")
        let slots = OverviewCompactAccountRow.slots(of: snapshot, provider: .grok)
        let row = OverviewCompactAccountRow(
            name: "Grok",
            shortWindow: slots.short,
            longWindow: slots.long,
            width: 340,
            provider: .grok,
            infersPeriodFromReset: false)
        #expect(row.lines.map(\.label) == ["—"])
    }

    @Test
    func `a reading above zero is at least a dot and zero has no fill`() {
        #expect(UsageBar.fillWidth(used: 0, barWidth: 100, height: 5) == 0)
        #expect(UsageBar.fillWidth(used: 1, barWidth: 100, height: 5) == 5)
        #expect(UsageBar.fillWidth(used: 50, barWidth: 100, height: 5) == 50)
        #expect(UsageBar.fillWidth(used: 120, barWidth: 100, height: 5) == 100)
    }
}
