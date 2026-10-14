import Foundation

public enum ClaudeMagpieAccountReaderError: LocalizedError, Sendable {
    case invalidURL
    case httpStatus(Int)
    case responseTooLarge(byteCount: Int)
    case noActiveUsage

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The magpie quotas URL is not a valid http(s) URL."
        case let .httpStatus(status):
            "magpie returned HTTP \(status)."
        case let .responseTooLarge(byteCount):
            "magpie returned \(byteCount) bytes; refusing to parse more than " +
                "\(ClaudeMagpieAccountReader.maxResponseBytes)."
        case .noActiveUsage:
            "magpie reports no Claude account with usage."
        }
    }
}

/// Reads Claude subscription accounts from the local magpie gateway's quota endpoint.
///
/// The endpoint is unauthenticated and returns usage only. CodexBar sends no credentials and
/// never reads Claude Code or magpie credential storage for this source.
public enum ClaudeMagpieAccountReader {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let defaultQuotasURL = "http://127.0.0.1:3425/v1/magpie/quotas"
    public static let maxResponseBytes = 1_048_576
    public static let defaultTimeout: TimeInterval = 10

    public static func quotasURL(from configured: String?) -> URL? {
        let raw = configured?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let text = raw.isEmpty ? self.defaultQuotasURL : raw
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil
        else { return nil }
        return url
    }

    public static func readAccounts(
        quotasURL configured: String?,
        now: Date = Date(),
        transport: Transport = Self.urlSessionTransport) async throws -> [ProviderAccountUsageSnapshot]
    {
        guard let url = self.quotasURL(from: configured) else {
            throw ClaudeMagpieAccountReaderError.invalidURL
        }
        var request = URLRequest(url: url, timeoutInterval: self.defaultTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClaudeMagpieAccountReaderError.httpStatus(http.statusCode)
        }
        guard data.count <= self.maxResponseBytes else {
            throw ClaudeMagpieAccountReaderError.responseTooLarge(byteCount: data.count)
        }
        return try ClaudeMagpieAccountProjection.accountSnapshots(from: data, now: now)
    }

    public static let urlSessionTransport: Transport = { request in
        try await URLSession.shared.data(for: request)
    }
}
