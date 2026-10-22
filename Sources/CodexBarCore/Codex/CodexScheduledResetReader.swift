import Foundation

/// A Codex usage reset announced for a future time, as reported by the unofficial codex-resets.com tracker.
public struct CodexScheduledReset: Sendable, Equatable {
    public let scheduledFor: Date
    /// The announcement the tracker cites; nil unless it is an https URL.
    public let sourceURL: URL?

    public init(scheduledFor: Date, sourceURL: URL?) {
        self.scheduledFor = scheduledFor
        self.sourceURL = sourceURL
    }

    /// A reset whose time has passed is no longer news, even while the tracker's cache still lists it.
    public func isPending(at now: Date) -> Bool {
        self.scheduledFor > now
    }
}

/// Reads the next scheduled Codex reset from codex-resets.com with a single unauthenticated GET.
///
/// The service is third-party and its data comes from social posts, so every field is read leniently:
/// anything missing or malformed means "no scheduled reset" rather than an error.
public enum CodexScheduledResetReader {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let statusURL = URL(string: "https://codex-resets.com/api/v1/status")!
    public static let maxResponseBytes = 262_144
    public static let defaultTimeout: TimeInterval = 10

    public static func read(transport: Transport = Self.urlSessionTransport) async throws -> CodexScheduledReset? {
        var request = URLRequest(url: self.statusURL, timeoutInterval: self.defaultTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard data.count <= self.maxResponseBytes else { throw URLError(.dataLengthExceedsMaximum) }
        return self.scheduledReset(from: data)
    }

    public static func scheduledReset(from data: Data) -> CodexScheduledReset? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let scheduled = payload["scheduled_reset"] as? [String: Any],
              scheduled["status"] as? String == "scheduled",
              let scheduledFor = (scheduled["scheduled_for"] as? String).flatMap(date(from:))
        else { return nil }
        let source = scheduled["source"] as? [String: Any]
        let url = (source?["url"] as? String).flatMap(URL.init(string:))
        return CodexScheduledReset(
            scheduledFor: scheduledFor,
            sourceURL: url?.scheme?.lowercased() == "https" ? url : nil)
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

    private static func date(from text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        return ISO8601DateFormatter().date(from: text)
    }
}
