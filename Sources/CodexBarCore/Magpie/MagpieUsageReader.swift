import Foundation

/// One day of magpie's usage series, at the local midnight magpie reports for it.
public struct MagpieUsageDay: Sendable, Equatable {
    public let day: Date
    public let cost: Double

    public init(day: Date, cost: Double) {
        self.day = day
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

    /// The series entry that falls on `date`'s day in `calendar`; a day the series omits costs nothing.
    public func cost(onSameDayAs date: Date, calendar: Calendar) -> Double {
        self.days.first { calendar.isDate($0.day, inSameDayAs: date) }?.cost ?? 0
    }
}

/// Reads the gateway's usage totals from the magpie endpoint that sits beside its quotas endpoint.
///
/// Like the quotas read, the request is unauthenticated and carries no provider credentials.
public enum MagpieUsageReader {
    public typealias Transport = MagpieQuotasReader.Transport

    public static let defaultPeriodDays = 30
    public static let maxResponseBytes = 1_048_576

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
        var request = URLRequest(url: url, timeoutInterval: MagpieQuotasReader.defaultTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MagpieQuotasReaderError.httpStatus(http.statusCode)
        }
        guard data.count <= self.maxResponseBytes else {
            throw MagpieQuotasReaderError.responseTooLarge(byteCount: data.count, limit: self.maxResponseBytes)
        }
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
            guard let day = ISO8601DateParser.parse(point.time) else { return nil as MagpieUsageDay? }
            // magpie sends a day's cost as an integer when nothing was spent and a decimal otherwise;
            // both decode as Double. A non-finite cost would poison every total, so the day is dropped.
            let cost = point.cost ?? 0
            guard cost.isFinite else { return nil }
            return MagpieUsageDay(day: day, cost: cost)
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

    // MARK: - Wire format

    private struct Response: Decodable {
        let period: String?
        let cost: Double?
        let calls: Int?
        let input: Int?
        let output: Int?
        let series: [Lenient<SeriesPoint>]?
    }

    /// One malformed day must not discard the rest of the series.
    private struct Lenient<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) throws {
            self.value = try? Value(from: decoder)
        }
    }

    private struct SeriesPoint: Decodable {
        let time: String?
        let cost: Double?
    }
}
