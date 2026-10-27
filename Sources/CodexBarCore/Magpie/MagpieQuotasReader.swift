import Foundation

public enum MagpieQuotasReaderError: LocalizedError, Sendable {
    case invalidURL
    case httpStatus(Int)
    case responseTooLarge(byteCount: Int, limit: Int)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The magpie quotas URL is not a valid http(s) URL."
        case let .httpStatus(status):
            "magpie returned HTTP \(status)."
        case let .responseTooLarge(byteCount, limit):
            "magpie returned \(byteCount) bytes; refusing to parse more than \(limit)."
        case .malformedResponse:
            "magpie returned a quota response CodexBar cannot read."
        }
    }
}

public struct MagpieResetCredits: Sendable, Equatable {
    /// One entry per credit, earliest first; a credit with no known expiry is nil and sorts last.
    public let expirations: [Date?]

    public var count: Int {
        self.expirations.count
    }

    public var nextExpiry: Date? {
        self.expirations.first.flatMap(\.self)
    }

    public init(expirations: [Date?]) {
        self.expirations = expirations.sorted { lhs, rhs in
            switch (lhs, rhs) {
            case let (lhs?, rhs?): lhs < rhs
            case (_?, nil): true
            default: false
            }
        }
    }
}

/// One provider row from magpie's quota response, projected leniently so a malformed sibling
/// row never discards the rest.
public struct MagpieQuotaRow: Sendable, Equatable {
    public let provider: String
    /// magpie's own card title ("ZCode", "ZCode · office" for a remote magpie's card); nil when absent.
    public let name: String?
    /// Display-only source email parsed from `user`; empty when magpie reports no user.
    public let email: String
    public let organization: String
    public let alias: String?
    public let isLast: Bool
    public let readAt: Date?
    public let windows: [MagpieQuotaWindow]
    public let error: String?
    public let resetCredits: MagpieResetCredits?

    public init(
        provider: String,
        email: String,
        organization: String,
        alias: String?,
        isLast: Bool,
        readAt: Date?,
        windows: [MagpieQuotaWindow],
        error: String? = nil,
        resetCredits: MagpieResetCredits? = nil,
        name: String? = nil)
    {
        self.provider = provider
        self.name = name
        self.email = email
        self.organization = organization
        self.alias = alias
        self.isLast = isLast
        self.readAt = readAt
        self.windows = windows
        self.error = error
        self.resetCredits = resetCredits
    }
}

/// Reads every provider's quota rows from the local magpie gateway with a single GET.
///
/// The endpoint is unauthenticated and returns usage only. CodexBar sends no credentials and
/// never reads provider credential storage for this source.
public enum MagpieQuotasReader {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let defaultQuotasURL = "http://127.0.0.1:3425/v1/magpie/quotas"
    public static let maxResponseBytes = 1_048_576
    public static let defaultTimeout: TimeInterval = 10
    static let userSeparator = " · "

    public static func quotasURL(from configured: String?) -> URL? {
        let raw = configured?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = raw.isEmpty ? self.defaultQuotasURL : raw
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil,
              url.user == nil, url.password == nil
        else { return nil }
        return url
    }

    /// Performs the one GET shared by every provider in a refresh round. The request carries no
    /// authentication headers.
    public static func readRows(
        quotasURL configured: String?,
        transport: Transport = Self.urlSessionTransport) async throws -> [MagpieQuotaRow]
    {
        guard let url = self.quotasURL(from: configured) else {
            throw MagpieQuotasReaderError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: self.defaultTimeout)
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
        return try self.rows(from: data)
    }

    public static func rows(from data: Data) throws -> [MagpieQuotaRow] {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw MagpieQuotasReaderError.malformedResponse
        }
        return response.data.compactMap(\.value).map(Self.row)
    }

    public static let urlSessionTransport: Transport = { request in
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return try await session.data(for: request)
    }

    // MARK: - Wire format

    private struct Response: Decodable {
        let data: [Lenient<Row>]
    }

    /// One malformed row must not discard its siblings.
    private struct Lenient<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) throws {
            self.value = try? Value(from: decoder)
        }
    }

    private struct Row: Decodable {
        let provider: String
        let name: String?
        let user: String?
        let alias: String?
        let last: Bool?
        let readAt: String?
        let windows: [Lenient<Window>]?
        let error: String?
        let resets: Lenient<Resets>?
    }

    private struct Resets: Decodable {
        let count: Int?
        let until: Lenient<String>?
        let each: Lenient<[Lenient<Reset>]>?

        var credits: MagpieResetCredits? {
            guard let count, count > 0 else { return nil }
            let listed = (self.each?.value ?? [])
                .compactMap { ISO8601DateParser.parse($0.value?.until?.value) }
                .sorted()
                .prefix(count)
            // `count` is authoritative: credits magpie did not itemise take the shared expiry, or none.
            let shared = ISO8601DateParser.parse(self.until?.value)
            return MagpieResetCredits(
                expirations: listed.map(Optional.some) + Array(repeating: shared, count: count - listed.count))
        }
    }

    private struct Reset: Decodable {
        let until: Lenient<String>?
    }

    private struct Window: Decodable {
        let name: String?
        let used: Double?
        let resetsAt: String?
        let pool: String?
        let unlimited: Lenient<Bool>?
    }

    private static func row(_ row: Row) -> MagpieQuotaRow {
        let (email, organization) = self.splitUser(row.user)
        let alias = row.alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = row.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let windows = (row.windows ?? []).compactMap(\.value).compactMap { window -> MagpieQuotaWindow? in
            // Negative usage is malformed; values above 100 are reported as-is and the UI clamps.
            guard let used = window.used, used.isFinite, used >= 0, let name = window.name else { return nil }
            return MagpieQuotaWindow(
                name: name,
                usedPercent: used,
                resetsAt: ISO8601DateParser.parse(window.resetsAt),
                pool: window.pool.flatMap { $0.isEmpty ? nil : $0 },
                unlimited: window.unlimited?.value == true)
        }
        return MagpieQuotaRow(
            provider: row.provider,
            email: email,
            organization: organization,
            alias: alias.isEmpty ? nil : alias,
            isLast: row.last == true,
            readAt: ISO8601DateParser.parse(row.readAt),
            windows: windows,
            error: row.error,
            resetCredits: row.resets?.value?.credits,
            name: name.isEmpty ? nil : name)
    }

    /// magpie formats `user` as "<email> · <organization>"; either side may be absent.
    static func splitUser(_ raw: String?) -> (email: String, organization: String) {
        let user = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let range = user.range(of: self.userSeparator) else { return (user, "") }
        return (
            String(user[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
            String(user[range.upperBound...]).trimmingCharacters(in: .whitespaces))
    }

    // MARK: - History

    /// Seven days covers a weekly window's whole cycle, which is all the curve and the pace fit read.
    public static let historyDays = 7
    /// A week of readings is a few hundred KB per handful of accounts; the cap leaves room for many
    /// more accounts while still refusing a runaway body.
    public static let maxHistoryResponseBytes = 16 * 1_048_576

    /// The history endpoint sits under the configured quotas URL: `<quotas>/history?days=N`.
    public static func historyURL(from configured: String?, days: Int = Self.historyDays) -> URL? {
        guard let quotas = self.quotasURL(from: configured),
              var components = URLComponents(url: quotas, resolvingAgainstBaseURL: false)
        else { return nil }
        components.path = (components.path.hasSuffix("/") ? components.path : components.path + "/") + "history"
        components.queryItems = [URLQueryItem(name: "days", value: String(days))]
        return components.url
    }

    /// Reads every account's window readings with one unauthenticated GET, like `readRows`.
    public static func readHistory(
        quotasURL configured: String?,
        transport: Transport = Self.urlSessionTransport) async throws -> MagpieQuotaHistory
    {
        guard let url = self.historyURL(from: configured) else {
            throw MagpieQuotasReaderError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: self.defaultTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MagpieQuotasReaderError.httpStatus(http.statusCode)
        }
        guard data.count <= self.maxHistoryResponseBytes else {
            throw MagpieQuotasReaderError.responseTooLarge(byteCount: data.count, limit: self.maxHistoryResponseBytes)
        }
        return try self.history(from: data)
    }

    public static func history(from data: Data) throws -> MagpieQuotaHistory {
        let response: HistoryResponse
        do {
            response = try JSONDecoder().decode(HistoryResponse.self, from: data)
        } catch {
            throw MagpieQuotasReaderError.malformedResponse
        }
        // One formatter pair for the whole body: a week holds thousands of timestamps.
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        func date(_ raw: String?) -> Date? {
            guard let raw, !raw.isEmpty else { return nil }
            return fractional.date(from: raw) ?? plain.date(from: raw)
        }
        let accounts = response.data.compactMap(\.value).map { account in
            MagpieQuotaHistoryAccount(
                provider: account.provider,
                user: account.user ?? "",
                lines: (account.lines ?? []).compactMap(\.value).compactMap { line in
                    guard let name = line.name else { return nil }
                    let points = (line.points ?? []).compactMap(\.value).compactMap { point in
                        // Same rule as quota windows: a reading must be a finite, non-negative percent.
                        guard let at = date(point.at), let left = point.left, left.isFinite, left >= 0
                        else { return nil as MagpieQuotaHistoryPoint? }
                        return MagpieQuotaHistoryPoint(
                            at: at,
                            left: left,
                            start: date(point.start),
                            resetsAt: date(point.resetsAt))
                    }
                    return MagpieQuotaHistoryAccount.Line(name: name, points: points)
                })
        }
        return MagpieQuotaHistory(accounts: accounts)
    }

    private struct HistoryResponse: Decodable {
        let data: [Lenient<HistoryAccount>]
    }

    private struct HistoryAccount: Decodable {
        let provider: String
        let user: String?
        let lines: [Lenient<HistoryLine>]?
    }

    private struct HistoryLine: Decodable {
        let name: String?
        let points: [Lenient<HistoryPoint>]?
    }

    private struct HistoryPoint: Decodable {
        let at: String?
        let left: Double?
        let start: String?
        let resetsAt: String?
    }
}
