import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct MagpieUsageReaderTests {
    /// Shape of magpie `GET /v1/magpie/usage`: totals at the top and a day per series entry, where a
    /// quiet day's cost arrives as `0` and a busy one's as a decimal.
    private static let usageJSON = """
    {"period":"30d","since":"2026-10-01T00:00:00+08:00","calls":125741,"errors":1688,
     "input":233018488,"output":77983676,"cache_read":11017017596,"reasoning":20811284,
     "cost":5193.252665556741,"unpriced":707,
     "bucket":"day","series":[
       {"label":"Oct 1","time":"2026-10-01T00:00:00+08:00","calls":0,"cost":0},
       {"label":"Oct 29","time":"2026-10-29T00:00:00+08:00","calls":4877,"cost":421.49456679999867},
       {"label":"Oct 30","time":"2026-10-30T00:00:00+08:00","calls":65,"cost":85.1}
     ]}
    """

    private static func calendar(_ identifier: String = "Asia/Shanghai") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    private static func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test
    func `totals and today's series entry fill the card`() throws {
        let summary = try MagpieUsageReader.usage(from: Data(Self.usageJSON.utf8))
        let model = OverviewUsageCardModel(
            summary: summary,
            now: Self.date("2026-10-30T12:02:00+08:00"),
            calendar: Self.calendar())

        #expect(model.titleText == "Usage & Spend · 30d")
        #expect(model.totalSpendText == "$5,193.25")
        #expect(model.todaySpendText == "$85.10")
        #expect(model.tokenText == "311M")
        #expect(model.callText == "126K")
    }

    @Test
    func `today follows the gateway's calendar date when the Mac is in another zone`() throws {
        // The gateway names Oct 30 at its +08:00 midnight; a Mac in New York reading the same instant
        // is still on Oct 29, but its own calendar day is Oct 30 and the card must say so.
        let summary = try MagpieUsageReader.usage(from: Data(Self.usageJSON.utf8))
        let model = OverviewUsageCardModel(
            summary: summary,
            now: Self.date("2026-10-30T12:02:00-04:00"),
            calendar: Self.calendar("America/New_York"))

        #expect(model.todaySpendText == "$85.10")
    }

    @Test
    func `a Japanese calendar still reads today as the gateway's Gregorian date`() throws {
        // The same day numbered in a Japanese calendar is year 8 of Reiwa; magpie names it 2026-10-30.
        let summary = try MagpieUsageReader.usage(from: Data(Self.usageJSON.utf8))
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let model = OverviewUsageCardModel(
            summary: summary,
            now: Self.date("2026-10-30T12:02:00+08:00"),
            calendar: japanese)

        #expect(model.todaySpendText == "$85.10")
    }

    @Test
    func `a day the series omits costs nothing today`() throws {
        let summary = try MagpieUsageReader.usage(from: Data(Self.usageJSON.utf8))
        let model = OverviewUsageCardModel(
            summary: summary,
            now: Self.date("2026-10-31T09:00:00+08:00"),
            calendar: Self.calendar())

        #expect(model.todaySpendText == "$0.00")
        #expect(model.totalSpendText == "$5,193.25")
    }

    @Test
    func `a quiet day's integer cost decodes like a decimal one`() throws {
        let summary = try MagpieUsageReader.usage(from: Data(Self.usageJSON.utf8))

        #expect(summary.days.count == 3)
        #expect(summary.days.first?.cost == 0)
        #expect(summary.periodDays == 30)
        #expect(summary.calls == 125_741)
        #expect(summary.tokenCount == 233_018_488 + 77_983_676)
    }

    @Test
    func `the usage endpoint sits beside the configured quotas endpoint`() {
        #expect(
            MagpieUsageReader.usageURL(fromQuotasURL: nil)
                == URL(string: "http://127.0.0.1:3425/v1/magpie/usage"))
        #expect(
            MagpieUsageReader.usageURL(fromQuotasURL: "http://magpie.lan:9000/gw/magpie/quotas")
                == URL(string: "http://magpie.lan:9000/gw/magpie/usage"))
        #expect(MagpieUsageReader.usageURL(fromQuotasURL: "not a url") == nil)
    }

    @Test
    func `an unreadable day is dropped without losing the rest`() throws {
        let json = """
        {"period":"7d","cost":12.5,"calls":4,"input":10,"output":5,
         "series":[{"time":"2026-10-30T00:00:00+08:00","cost":12.5},{"time":"whenever","cost":3}]}
        """
        let summary = try MagpieUsageReader.usage(from: Data(json.utf8))

        #expect(summary.days.count == 1)
        #expect(summary.periodDays == 7)
        #expect(summary.totalCost == 12.5)
    }

    @Test
    func `a body that decodes but carries no usage fields is rejected`() throws {
        // The quota shape decodes cleanly here; showing it as a zeroed usage window would hide the
        // wrong endpoint behind a plausible card.
        let body = Data("""
        {"data":[{"provider":"claude","windows":[{"name":"5 hours","used":1}]}]}
        """.utf8)
        var caught = false
        do {
            _ = try MagpieUsageReader.usage(from: body)
        } catch MagpieQuotasReaderError.malformedUsageResponse {
            caught = true
        }
        #expect(caught)
    }
}
