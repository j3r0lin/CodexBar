import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct MagpiePaceTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let day: TimeInterval = 86400

    /// A "7 days" window with half of it elapsed.
    private static func weekly(
        _ name: String = "7 days",
        used: Double,
        remaining: TimeInterval = 3.5 * day) -> MagpieQuotaWindow
    {
        MagpieQuotaWindow(name: name, usedPercent: used, resetsAt: self.now.addingTimeInterval(remaining))
    }

    private static func row(
        _ opaque: String = "claude:a",
        windows: [MagpieQuotaWindow],
        readAt: Date? = nil) -> OverviewUsageRow
    {
        OverviewUsageRow.magpie(
            account: MagpieAccountSnapshot(
                id: ProviderAccountIdentity(source: "magpie", opaqueID: opaque),
                provider: MagpieProviderMapping.reference(for: "claude"),
                displayLabel: opaque,
                accountEmail: nil,
                ordinal: 1,
                windows: windows,
                readAt: readAt,
                isActive: true,
                error: nil),
            providerName: "Claude",
            accountName: opaque)
    }

    private static func weeklyLine(of row: OverviewUsageRow) -> OverviewCompactAccountRow.Line? {
        row.compactLines(now: self.now)?.first { $0.label == "7d" }
    }

    @Test
    func `half the week used at half the week elapsed is on pace`() throws {
        let line = try #require(Self.weeklyLine(of: Self.row(windows: [Self.weekly(used: 50)])))
        #expect(try abs(#require(line.pacePercent) - 50) < 0.001)
        #expect(line.paceTone == .neutral)
    }

    @Test
    func `heavy use before mid-week is a deficit that runs out before reset`() throws {
        let window = OverviewUsageRow.NamedWindow(window: Self.weekly(used: 80))
        let pace = try #require(window.pace(now: Self.now))
        #expect(pace.deltaPercent > 0)
        let eta = try #require(pace.etaSeconds)
        #expect(eta < 3.5 * Self.day)
        let line = try #require(Self.weeklyLine(of: Self.row(windows: [Self.weekly(used: 80)])))
        #expect(line.paceTone == .runsOut)
    }

    @Test
    func `light use before mid-week is a reserve that lasts until reset`() throws {
        let window = OverviewUsageRow.NamedWindow(window: Self.weekly(used: 20))
        let pace = try #require(window.pace(now: Self.now))
        #expect(pace.deltaPercent < 0)
        #expect(pace.willLastToReset)
        let line = try #require(Self.weeklyLine(of: Self.row(windows: [Self.weekly(used: 20)])))
        #expect(line.paceTone == .neutral)
        #expect(line.pacePercent != nil)
    }

    @Test
    func `model-scoped weekly windows get pace and monthly or unknown windows do not`() {
        let scoped = OverviewUsageRow.NamedWindow(window: Self.weekly("7 days · Fable", used: 60))
        #expect(scoped.pace(now: Self.now) != nil)
        let monthly = OverviewUsageRow.NamedWindow(window: Self.weekly("Month", used: 60, remaining: 10 * Self.day))
        #expect(monthly.pace(now: Self.now) == nil)
        let unknown = OverviewUsageRow.NamedWindow(window: Self.weekly("Burst", used: 60))
        #expect(unknown.pace(now: Self.now) == nil)
    }

    @Test
    func `every window with a pace gets its own tick`() throws {
        let session = MagpieQuotaWindow(
            name: "5 hours",
            usedPercent: 40,
            resetsAt: Self.now.addingTimeInterval(2.5 * 3600))
        let unknown = MagpieQuotaWindow(name: "Credits", usedPercent: 10, resetsAt: nil)
        let lines = try #require(Self.row(windows: [session, Self.weekly(used: 80), unknown])
            .compactLines(now: Self.now))
        #expect(lines.map { $0.pacePercent != nil } == [true, true, false])
    }

    @Test
    func `two accounts of one provider get independent pace`() throws {
        let heavy = try #require(Self.weeklyLine(of: Self.row("claude:a", windows: [Self.weekly(used: 80)])))
        let light = try #require(Self.weeklyLine(of: Self.row("claude:b", windows: [Self.weekly(used: 20)])))
        #expect(heavy.pacePercent == light.pacePercent)
        #expect(heavy.paceTone != light.paceTone)
    }

    @Test
    func `detail blocks say whether the window lasts to its reset`() throws {
        let heavy = try #require(AccountUsageDetailView.blocks(
            of: [OverviewUsageRow.NamedWindow(window: Self.weekly(used: 80))],
            now: Self.now).first)
        guard case let .runsOut(date) = heavy.outlook else {
            Issue.record("expected a run-out, got \(String(describing: heavy.outlook))")
            return
        }
        #expect(date < Self.now.addingTimeInterval(3.5 * Self.day))
        let light = try #require(AccountUsageDetailView.blocks(
            of: [OverviewUsageRow.NamedWindow(window: Self.weekly(used: 20))],
            now: Self.now).first)
        #expect(light.outlook == .lastsPastReset)
    }

    @Test
    func `detail blocks of a monthly window carry no pace`() throws {
        let windows = [OverviewUsageRow.NamedWindow(window: Self.weekly("Month", used: 60, remaining: 10 * Self.day))]
        let block = try #require(AccountUsageDetailView.blocks(of: windows, now: Self.now).first)
        #expect(block.outlook == nil)
    }

    /// Readings of the current week, one an hour up to now, falling `perHour` points from `startLeft`.
    private static func readings(
        hours: Int,
        startLeft: Double,
        perHour: Double,
        remaining: TimeInterval = 3.5 * day) -> [MagpieQuotaHistoryPoint]
    {
        let reset = self.now.addingTimeInterval(remaining)
        return (0...hours).map { hour in
            MagpieQuotaHistoryPoint(
                at: self.now.addingTimeInterval(TimeInterval(hour - hours) * 3600),
                left: startLeft - Double(hour) * perHour,
                start: reset.addingTimeInterval(-7 * self.day),
                resetsAt: reset)
        }
    }

    private static func weeklyLine(window: MagpieQuotaWindow, history: [MagpieQuotaHistoryPoint])
        -> OverviewCompactAccountRow.Line?
    {
        let named = OverviewUsageRow.NamedWindow(window: window, history: history)
        let row = OverviewUsageRow(
            groupKey: "claude",
            providerName: "Claude",
            nativeProvider: .claude,
            accountID: nil,
            accountName: nil,
            namedWindows: [named],
            snapshot: nil,
            model: nil,
            errorText: nil,
            showsErrorFlag: false,
            detailErrorText: nil,
            readAt: nil)
        return row.compactLines(now: self.now)?.first
    }

    @Test
    func `a steep recent burn runs out before reset although the linear pace lasts`() throws {
        // 20% used at mid-week lasts on the linear pace, but the last six hours burned 3 points an hour.
        let line = try #require(Self.weeklyLine(
            window: Self.weekly(used: 20),
            history: Self.readings(hours: 6, startLeft: 100, perHour: 3)))
        #expect(line.paceTone == .runsOut)
        #expect(try abs(#require(line.pacePercent) - 50) < 0.001)
    }

    @Test
    func `a slow recent burn lasts although usage is ahead of the even burn`() throws {
        // 80% used at mid-week runs out on the linear pace; the readings barely move.
        let line = try #require(Self.weeklyLine(
            window: Self.weekly(used: 80),
            history: Self.readings(hours: 6, startLeft: 20.6, perHour: 0.1)))
        #expect(line.paceTone == .deficit)
    }

    @Test
    func `too few readings fall back to the linear pace`() throws {
        let line = try #require(Self.weeklyLine(
            window: Self.weekly(used: 20),
            history: Array(Self.readings(hours: 6, startLeft: 100, perHour: 3).suffix(2))))
        #expect(line.paceTone == .neutral)
    }

    @Test
    func `a reading older than three refresh intervals is stale`() {
        let threshold = OverviewUsageRow.staleThreshold(for: .fiveMinutes)
        let fresh = Self.row(windows: [Self.weekly(used: 50)], readAt: Self.now.addingTimeInterval(-10 * 60))
        let old = Self.row(windows: [Self.weekly(used: 50)], readAt: Self.now.addingTimeInterval(-20 * 60))
        #expect(!fresh.isStale(now: Self.now, threshold: threshold))
        #expect(old.isStale(now: Self.now, threshold: threshold))
    }

    @Test
    func `manual refresh never marks a reading stale`() {
        let old = Self.row(windows: [Self.weekly(used: 50)], readAt: Self.now.addingTimeInterval(-86400))
        #expect(!old.isStale(now: Self.now, threshold: OverviewUsageRow.staleThreshold(for: .manual)))
    }
}
