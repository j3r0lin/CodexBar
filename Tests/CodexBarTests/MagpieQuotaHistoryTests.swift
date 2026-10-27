import CodexBarCore
import Foundation
import Testing

struct MagpieQuotaHistoryTests {
    private static let start = Date(timeIntervalSince1970: 1_800_000_000)
    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 86400

    private static func point(
        hours: Double,
        left: Double,
        reset: Date? = Self.start.addingTimeInterval(7 * Self.day)) -> MagpieQuotaHistoryPoint
    {
        MagpieQuotaHistoryPoint(
            at: self.start.addingTimeInterval(hours * self.hour),
            left: left,
            start: reset.map { _ in self.start },
            resetsAt: reset)
    }

    private static func cycle(_ points: [MagpieQuotaHistoryPoint], now: Date) throws -> MagpieQuotaTrend.Cycle {
        try #require(MagpieQuotaTrend.currentCycle(points: points, resetsAt: points.last?.resetsAt, now: now))
    }

    // MARK: - Fitted run-out

    @Test
    func `a steady burn runs out where its line meets zero`() throws {
        // 2 points an hour from full: empty 50 hours in, well before the weekly reset.
        let points = (0...10).map { Self.point(hours: Double($0), left: 100 - 2 * Double($0)) }
        let now = Self.start.addingTimeInterval(10 * Self.hour)
        let eta = try MagpieQuotaTrend.eta(points: points, cycle: Self.cycle(points, now: now), now: now)
        guard case let .runsOut(date) = eta else {
            Issue.record("expected a run-out, got \(String(describing: eta))")
            return
        }
        #expect(abs(date.timeIntervalSince(Self.start.addingTimeInterval(50 * Self.hour))) < 60)
    }

    @Test
    func `a slow burn lasts past the reset`() throws {
        let points = (0...10).map { Self.point(hours: Double($0), left: 100 - 0.1 * Double($0)) }
        let now = Self.start.addingTimeInterval(10 * Self.hour)
        #expect(try MagpieQuotaTrend.eta(points: points, cycle: Self.cycle(points, now: now), now: now)
            == .lastsPastReset)
    }

    @Test
    func `fewer than three readings or less than an hour of them give no fit`() throws {
        let two = [Self.point(hours: 0, left: 100), Self.point(hours: 5, left: 50)]
        let twoNow = Self.start.addingTimeInterval(5 * Self.hour)
        #expect(try MagpieQuotaTrend.eta(points: two, cycle: Self.cycle(two, now: twoNow), now: twoNow) == nil)

        let brief = (0...5).map { Self.point(hours: Double($0) / 10, left: 100 - Double($0)) }
        let briefNow = Self.start.addingTimeInterval(0.5 * Self.hour)
        #expect(try MagpieQuotaTrend.eta(points: brief, cycle: Self.cycle(brief, now: briefNow), now: briefNow)
            == nil)
    }

    @Test
    func `only the current cycle's readings count`() throws {
        // Last week burned fast and reset at `start`; this week has barely moved.
        let previous = (0...10).map {
            MagpieQuotaHistoryPoint(
                at: Self.start.addingTimeInterval(Double($0 - 20) * Self.hour),
                left: 60 - 5 * Double($0),
                start: Self.start.addingTimeInterval(-7 * Self.day),
                resetsAt: Self.start)
        }
        let current = (0...10).map { Self.point(hours: Double($0), left: 100 - 0.1 * Double($0)) }
        let points = previous + current
        let now = Self.start.addingTimeInterval(10 * Self.hour)
        let cycle = try Self.cycle(points, now: now)
        #expect(cycle.start == Self.start)
        #expect(MagpieQuotaTrend.cyclePoints(points, cycle: cycle, now: now) == current)
        #expect(MagpieQuotaTrend.eta(points: points, cycle: cycle, now: now) == .lastsPastReset)
    }

    @Test
    func `a refill without a new reset starts a new cycle`() {
        let reset = Self.start.addingTimeInterval(7 * Self.day)
        let before = Self.point(hours: 1, left: 40, reset: reset)
        #expect(MagpieQuotaTrend.cycleBreak(before, Self.point(hours: 2, left: 90, reset: reset)))
        #expect(!MagpieQuotaTrend.cycleBreak(before, Self.point(hours: 2, left: 38, reset: reset)))
        #expect(MagpieQuotaTrend.cycleBreak(
            before,
            Self.point(hours: 2, left: 40, reset: reset.addingTimeInterval(Self.day))))
    }

    // MARK: - Reading the endpoint

    @Test
    func `history sits under the configured quotas URL`() {
        #expect(MagpieQuotasReader.historyURL(from: nil)?.absoluteString
            == "http://127.0.0.1:3425/v1/magpie/quotas/history?days=7")
        #expect(MagpieQuotasReader.historyURL(from: "http://127.0.0.1:9000/quotas/")?.absoluteString
            == "http://127.0.0.1:9000/quotas/history?days=7")
    }

    @Test
    func `history lines land on the account rows they belong to`() throws {
        let rows = [
            MagpieQuotaRow(
                provider: "claude",
                email: "first@example.com",
                organization: "Example Org",
                alias: nil,
                isLast: true,
                readAt: nil,
                windows: [MagpieQuotaWindow(name: "7 days", usedPercent: 10, resetsAt: nil)]),
            MagpieQuotaRow(
                provider: "kimi",
                email: "",
                organization: "",
                alias: nil,
                isLast: false,
                readAt: nil,
                windows: [MagpieQuotaWindow(name: "5 hours", usedPercent: 10, resetsAt: nil)]),
        ]
        let accounts = MagpieAccountProjection.snapshots(from: rows)
        let claude = try #require(accounts.first { $0.provider.wireID == "claude" })
        let kimi = try #require(accounts.first { $0.provider.nativeProvider == .kimi })
        // magpie lowercases the history's user; a retired wire ID (kimi-code) still names Kimi; a malformed
        // point, line, and account are dropped without their siblings.
        let body = """
        {"object":"list","data":[
          {"provider":"claude","user":"first@example.com · example org","lines":[
            {"name":"7 days","points":[
              {"at":"2027-01-15T08:00:00Z","left":90,"start":"2027-01-14T00:00:00Z","resetsAt":"2027-01-21T00:00:00Z"},
              {"at":"not a date","left":80},
              {"at":"2027-01-15T09:00:00.5Z","left":85}]},
            {"points":[]}]},
          {"provider":"kimi-code","user":"","lines":[
            {"name":"5 hours","points":[{"at":"2027-01-15T08:00:00Z","left":50}]}]},
          {"user":"orphan"}
        ]}
        """
        let history = try MagpieQuotasReader.history(from: Data(body.utf8))
        #expect(history.points(for: claude.id, window: "7 days").map(\.left) == [90, 85])
        #expect(history.points(for: kimi.id, window: "5 hours").map(\.left) == [50])
        #expect(history.points(for: claude.id, window: "5 hours").isEmpty)
    }

    @Test
    func `a remote magpie's history lands on its account in the native card`() throws {
        let rows = try MagpieQuotasReader.rows(from: Data("""
        {"data":[{"provider":"office/codex","user":"remote@example.com","from":"office",
          "windows":[{"name":"5 hours","used":10}]}]}
        """.utf8))
        let account = try #require(MagpieAccountProjection.snapshots(from: rows).first)
        let history = try MagpieQuotasReader.history(from: Data("""
        {"data":[{"provider":"office/codex","user":"remote@example.com","lines":[
          {"name":"5 hours","points":[{"at":"2027-01-15T08:00:00Z","left":90}]}]}]}
        """.utf8))
        #expect(history.points(for: account.id, window: "5 hours").map(\.left) == [90])
    }

    @Test
    func `an oversized history body is refused`() async {
        let transport: MagpieQuotasReader.Transport = { request in
            (
                Data(count: MagpieQuotasReader.maxHistoryResponseBytes + 1),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        await #expect(throws: MagpieQuotasReaderError.self) {
            try await MagpieQuotasReader.readHistory(quotasURL: nil, transport: transport)
        }
    }
}
