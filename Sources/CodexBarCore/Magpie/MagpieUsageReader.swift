import Foundation

/// One day of magpie's usage series, keyed by the calendar date magpie wrote for it rather than an
/// instant: magpie stamps each day at the gateway's own midnight, which need not be the Mac's.
public struct MagpieUsageDay: Sendable, Equatable {
    /// The `YYYY-MM-DD` prefix of the series entry's `time`, which carries the gateway's offset.
    public let dayKey: String
    public let cost: Double

    public init(dayKey: String, cost: Double) {
        self.dayKey = dayKey
        self.cost = cost
    }
}

/// magpie's spend and token totals for the usage window its gateway reports (30 days by default).
public struct MagpieUsageSummary: Sendable, Equatable {
    public let periodDays: Int
    public let totalCost: Double
    public let calls: Int
    public let inputTokens: Int
    public let outputTokens: Int
    /// The daily series, in the order magpie returned it; a day with no traffic may still be listed.
    public let days: [MagpieUsageDay]

    public init(
        periodDays: Int,
        totalCost: Double,
        calls: Int,
        inputTokens: Int,
        outputTokens: Int,
        days: [MagpieUsageDay])
    {
        self.periodDays = periodDays
        self.totalCost = totalCost
        self.calls = calls
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.days = days
    }

    public var tokenCount: Int {
        self.inputTokens + self.outputTokens
    }

    /// The series cost for `date`'s calendar day, compared as dates and not instants: a gateway in
    /// another zone still means "today" by the day it named, so the card and magpie agree.
    public func cost(onDayOf date: Date, calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return 0 }
        let key = String(format: "%04d-%02d-%02d", year, month, day)
        return self.days.first { $0.dayKey == key }?.cost ?? 0
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
        guard response.cost != nil || response.calls != nil || response.series != nil else {
            throw MagpieQuotasReaderError.malformedUsageResponse
        }
        let days = (response.series ?? []).compactMap(\.value).compactMap { point in
            guard let time = point.time, let dayKey = Self.dayKey(time) else {
                return nil as MagpieUsageDay?
            }
            // magpie sends a day's cost as an integer when nothing was spent and a decimal otherwise;
            // both decode as Double. A non-finite cost would poison every total, so the day is dropped.
            let cost = point.cost ?? 0
            guard cost.isFinite else { return nil }
            return MagpieUsageDay(dayKey: dayKey, cost: cost)
        }
        return MagpieUsageSummary(
            periodDays: Self.periodDays(response.period),
            totalCost: response.cost.flatMap { $0.isFinite ? $0 : nil } ?? 0,
            calls: response.calls ?? 0,
            inputTokens: response.input ?? 0,
            outputTokens: response.output ?? 0,
            days: days)
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

    private struct Response: Decodable {
        let period: String?
        let cost: Double?
        let calls: Int?
        let input: Int?
        let output: Int?
        let series: [Lenient<SeriesPoint>]?
    }

    private struct SeriesPoint: Decodable {
        let time: String?
        let cost: Double?
    }
}
