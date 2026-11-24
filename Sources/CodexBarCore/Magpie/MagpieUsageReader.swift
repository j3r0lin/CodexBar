import Foundation

/// Spend and token counts for one stretch of magpie's usage: the whole window, or one day of it.
public struct MagpieUsageTotals: Sendable, Equatable {
    public let cost: Double
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int
    public let cacheWriteTokens: Int

    public static let zero = MagpieUsageTotals(
        cost: 0, inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0)

    public init(cost: Double, inputTokens: Int, outputTokens: Int, cacheReadTokens: Int, cacheWriteTokens: Int) {
        self.cost = cost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
    }

    /// Every token the gateway moved. magpie's `input` excludes cached prompt tokens, so leaving the
    /// cache counts out would report a few percent of the real volume.
    public var tokenCount: Int {
        self.inputTokens + self.outputTokens + self.cacheReadTokens + self.cacheWriteTokens
    }

    /// The share of prompt tokens served from cache, or nil when no prompt tokens were sent.
    public var cacheHitRate: Double? {
        let prompt = self.inputTokens + self.cacheReadTokens + self.cacheWriteTokens
        guard prompt > 0 else { return nil }
        return Double(self.cacheReadTokens) / Double(prompt)
    }
}

/// One day of magpie's usage series, keyed by the calendar date magpie wrote for it rather than an
/// instant: magpie stamps each day at the gateway's own midnight, which need not be the Mac's.
public struct MagpieUsageDay: Sendable, Equatable {
    /// The `YYYY-MM-DD` prefix of the series entry's `time`, which carries the gateway's offset.
    public let dayKey: String
    public let totals: MagpieUsageTotals

    public init(dayKey: String, totals: MagpieUsageTotals) {
        self.dayKey = dayKey
        self.totals = totals
    }
}

/// magpie's spend and token totals for the usage window its gateway reports (30 days by default).
public struct MagpieUsageSummary: Sendable, Equatable {
    public let periodDays: Int
    public let total: MagpieUsageTotals
    /// The daily series, in the order magpie returned it; a day with no traffic may still be listed.
    public let days: [MagpieUsageDay]

    public init(periodDays: Int, total: MagpieUsageTotals, days: [MagpieUsageDay]) {
        self.periodDays = periodDays
        self.total = total
        self.days = days
    }

    /// The series totals for `date`'s calendar day, compared as dates and not instants: a gateway in
    /// another zone still means "today" by the day it named, so the card and magpie agree. A day the
    /// series leaves out had no traffic.
    ///
    /// The day is read from a Gregorian calendar carrying the caller's zone: magpie writes Gregorian
    /// dates, and a user's Japanese or Buddhist calendar would number the same day differently.
    public func totals(onDayOf date: Date, calendar: Calendar) -> MagpieUsageTotals {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = gregorian.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return .zero
        }
        let key = String(format: "%04d-%02d-%02d", year, month, day)
        return self.days.first { $0.dayKey == key }?.totals ?? .zero
    }
}

/// Reads the gateway's usage totals from the magpie endpoint that sits beside its quotas endpoint.
///
/// Like the quotas read, the request is unauthenticated and carries no provider credentials.
public enum MagpieUsageReader {
    public typealias Transport = MagpieQuotasReader.Transport

    static let defaultPeriodDays = 30
    /// The usage body carries a per-day series and magpie's session list; it is as large as the history
    /// read's and gets the same cap, which the quotas endpoint's 1 MiB would reject today.
    static let maxResponseBytes = MagpieQuotasReader.maxHistoryResponseBytes

    /// The usage endpoint is the sibling of the configured quotas endpoint, so both come from one
    /// gateway address.
    public static func usageURL(fromQuotasURL configured: String?) -> URL? {
        guard let quotas = MagpieQuotasReader.quotasURL(from: configured),
              var components = URLComponents(url: quotas, resolvingAgainstBaseURL: false)
        else { return nil }
        var parts = components.path.split(separator: "/", omittingEmptySubsequences: true)
        if parts.last == "quotas" {
            parts.removeLast()
        }
        parts.append("usage")
        components.path = "/" + parts.joined(separator: "/")
        components.queryItems = nil
        return components.url
    }

    public static func readUsage(
        quotasURL configured: String?,
        transport: Transport = MagpieQuotasReader.urlSessionTransport) async throws -> MagpieUsageSummary
    {
        guard let url = self.usageURL(fromQuotasURL: configured) else {
            throw MagpieQuotasReaderError.invalidURL
        }
        let data = try await MagpieQuotasReader.get(
            url,
            limit: self.maxResponseBytes,
            transport: transport)
        return try self.usage(from: data)
    }

    public static func usage(from data: Data) throws -> MagpieUsageSummary {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw MagpieQuotasReaderError.malformedUsageResponse
        }
        // A body with none of the usage fields is some other endpoint's answer (the quotas shape has
        // `data` and nothing else in common), not a usage window worth showing as zero.
        guard response.counts.cost != nil || response.calls != nil || response.series != nil else {
            throw MagpieQuotasReaderError.malformedUsageResponse
        }
        let days = (response.series ?? []).compactMap(\.value).compactMap { point in
            guard let time = point.time, let dayKey = Self.dayKey(time) else {
                return nil as MagpieUsageDay?
            }
            // A non-finite cost would poison every total, so the day is dropped.
            guard let totals = Self.totals(point.counts) else { return nil }
            return MagpieUsageDay(dayKey: dayKey, totals: totals)
        }
        return MagpieUsageSummary(
            periodDays: Self.periodDays(response.period),
            total: Self.totals(response.counts) ?? .zero,
            days: days)
    }

    /// magpie sends a cost as an integer when nothing was spent and a decimal otherwise; both decode
    /// as Double. Missing counts are zero.
    private static func totals(_ counts: Counts) -> MagpieUsageTotals? {
        let cost = counts.cost ?? 0
        guard cost.isFinite else { return nil }
        return MagpieUsageTotals(
            cost: cost,
            inputTokens: counts.input ?? 0,
            outputTokens: counts.output ?? 0,
            cacheReadTokens: counts.cacheRead ?? 0,
            cacheWriteTokens: counts.cacheWrite ?? 0)
    }

    /// magpie's period reads "30d"; anything unreadable falls back to the gateway's usual window.
    static func periodDays(_ period: String?) -> Int {
        guard let period,
              let days = Int(period.trimmingCharacters(in: CharacterSet(charactersIn: "dD"))),
              days > 0
        else { return self.defaultPeriodDays }
        return days
    }

    /// The date part of an ISO 8601 timestamp, read as written in its own offset. Parsing it as a
    /// `Date` would collapse gateway midnight and Mac midnight into one instant comparison.
    static func dayKey(_ time: String) -> String? {
        guard time.count >= 10 else { return nil }
        let key = String(time.prefix(10))
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, Int(parts[0]) != nil,
              parts[1].count == 2, Int(parts[1]) != nil,
              parts[2].count == 2, Int(parts[2]) != nil
        else { return nil }
        return key
    }

    // MARK: - Wire format

    /// The counts magpie writes both for the whole window and for each series day.
    private struct Counts: Decodable {
        let cost: Double?
        let input: Int?
        let output: Int?
        let cacheRead: Int?
        let cacheWrite: Int?

        enum CodingKeys: String, CodingKey {
            case cost, input, output
            case cacheRead = "cache_read"
            case cacheWrite = "cache_write"
        }
    }

    private struct Response: Decodable {
        let period: String?
        let calls: Int?
        let series: [Lenient<SeriesPoint>]?
        let counts: Counts

        enum CodingKeys: String, CodingKey {
            case period, calls, series
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.period = try container.decodeIfPresent(String.self, forKey: .period)
            self.calls = try container.decodeIfPresent(Int.self, forKey: .calls)
            self.series = try container.decodeIfPresent([Lenient<SeriesPoint>].self, forKey: .series)
            self.counts = try Counts(from: decoder)
        }
    }

    private struct SeriesPoint: Decodable {
        let time: String?
        let counts: Counts

        enum CodingKeys: String, CodingKey {
            case time
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.time = try container.decodeIfPresent(String.self, forKey: .time)
            self.counts = try Counts(from: decoder)
        }
    }
}
