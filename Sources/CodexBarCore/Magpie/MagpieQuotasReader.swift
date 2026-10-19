import Foundation

public enum MagpieQuotasReaderError: LocalizedError, Sendable {
    case invalidURL
    case httpStatus(Int)
    case responseTooLarge(byteCount: Int)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The magpie quotas URL is not a valid http(s) URL."
        case let .httpStatus(status):
            "magpie returned HTTP \(status)."
        case let .responseTooLarge(byteCount):
            "magpie returned \(byteCount) bytes; refusing to parse more than " +
                "\(MagpieQuotasReader.maxResponseBytes)."
        case .malformedResponse:
            "magpie returned a quota response CodexBar cannot read."
        }
    }
}

/// One provider row from magpie's quota response, projected leniently so a malformed sibling
/// row never discards the rest.
public struct MagpieQuotaRow: Sendable, Equatable {
    public let provider: String
    /// Display-only source email parsed from `user`; empty when magpie reports no user.
    public let email: String
    public let organization: String
    public let alias: String?
    public let isLast: Bool
    public let readAt: Date?
    public let windows: [MagpieQuotaWindow]
    public let error: String?

    public init(
        provider: String,
        email: String,
        organization: String,
        alias: String?,
        isLast: Bool,
        readAt: Date?,
        windows: [MagpieQuotaWindow],
        error: String? = nil)
    {
        self.provider = provider
        self.email = email
        self.organization = organization
        self.alias = alias
        self.isLast = isLast
        self.readAt = readAt
        self.windows = windows
        self.error = error
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
            throw MagpieQuotasReaderError.responseTooLarge(byteCount: data.count)
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
        let user: String?
        let alias: String?
        let last: Bool?
        let readAt: String?
        let windows: [Lenient<Window>]?
        let error: String?
    }

    private struct Window: Decodable {
        let name: String?
        let used: Double?
        let resetsAt: String?
    }

    private static func row(_ row: Row) -> MagpieQuotaRow {
        // magpie formats `user` as "<email> · <organization>"; either side may be absent.
        let user = row.user?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let email: String
        let organization: String
        if let range = user.range(of: self.userSeparator) {
            email = String(user[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            organization = String(user[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            email = user
            organization = ""
        }
        let alias = row.alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let windows = (row.windows ?? []).compactMap(\.value).compactMap { window -> MagpieQuotaWindow? in
            // Negative usage is malformed; values above 100 are reported as-is and the UI clamps.
            guard let used = window.used, used.isFinite, used >= 0, let name = window.name else { return nil }
            return MagpieQuotaWindow(
                name: name,
                usedPercent: used,
                resetsAt: ISO8601DateParser.parse(window.resetsAt))
        }
        return MagpieQuotaRow(
            provider: row.provider,
            email: email,
            organization: organization,
            alias: alias.isEmpty ? nil : alias,
            isLast: row.last == true,
            readAt: ISO8601DateParser.parse(row.readAt),
            windows: windows,
            error: row.error)
    }
}
