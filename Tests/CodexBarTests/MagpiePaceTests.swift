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
        #expect(line.paceText != nil)
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
        #expect(line.paceText != nil)
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
    func `pace phrase sits on the longest window with pace only`() throws {
        let session = MagpieQuotaWindow(
            name: "5 hours",
            usedPercent: 40,
            resetsAt: Self.now.addingTimeInterval(2.5 * 3600))
        let lines = try #require(Self.row(windows: [session, Self.weekly(used: 80)]).compactLines(now: Self.now))
        #expect(lines.map { $0.paceText != nil } == [false, true])
    }

    @Test
    func `two accounts of one provider get independent pace`() throws {
        let heavy = try #require(Self.weeklyLine(of: Self.row("claude:a", windows: [Self.weekly(used: 80)])))
        let light = try #require(Self.weeklyLine(of: Self.row("claude:b", windows: [Self.weekly(used: 20)])))
        #expect(heavy.paceText != light.paceText)
        #expect(heavy.paceTone != light.paceTone)
    }

    @Test
    func `detail blocks carry the pace line, the expected-usage marker and warning markers`() throws {
        let windows = [OverviewUsageRow.NamedWindow(window: Self.weekly(used: 80))]
        let block = try #require(AccountUsageDetailView.blocks(
            of: windows,
            now: Self.now,
            quotaWarningThresholds: [.weekly: [20]]).first)
        let marker = try #require(block.pacePercent)
        #expect(abs(marker - 50) < 0.001)
        #expect(block.paceLeftText != nil)
        #expect(block.paceRightText != nil)
        #expect(block.warningMarkerPercents == [80])
    }

    @Test
    func `detail blocks of a monthly window carry no pace and no warning markers`() throws {
        let windows = [OverviewUsageRow.NamedWindow(window: Self.weekly("Month", used: 60, remaining: 10 * Self.day))]
        let block = try #require(AccountUsageDetailView.blocks(
            of: windows,
            now: Self.now,
            quotaWarningThresholds: [.weekly: [20], .session: [20]]).first)
        #expect(block.pacePercent == nil)
        #expect(block.paceLeftText == nil)
        #expect(block.warningMarkerPercents.isEmpty)
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
