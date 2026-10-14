import Foundation

/// The only Claude fetch strategy while magpie owns Claude accounts. It reports the active magpie account's usage
/// and never falls back to a credential-based strategy.
struct ClaudeMagpieFetchStrategy: ProviderFetchStrategy {
    let id: String = "claude.magpie"
    let kind: ProviderFetchKind = .localProbe
    let quotasURL: String
    let transport: ClaudeMagpieAccountReader.Transport

    init(
        quotasURL: String,
        transport: @escaping ClaudeMagpieAccountReader.Transport = ClaudeMagpieAccountReader.urlSessionTransport)
    {
        self.quotasURL = quotasURL
        self.transport = transport
    }

    func isAvailable(_: ProviderFetchContext) async -> Bool {
        true
    }

    func fetch(_: ProviderFetchContext) async throws -> ProviderFetchResult {
        let accounts = try await ClaudeMagpieAccountReader.readAccounts(
            quotasURL: self.quotasURL,
            transport: self.transport)
        guard let active = accounts.first(where: \.isActive), let usage = active.snapshot else {
            throw ClaudeMagpieAccountReaderError.noActiveUsage
        }
        return self.makeResult(usage: usage, sourceLabel: ClaudeMagpieAccountProjection.sourceLabel)
    }

    func shouldFallback(on _: Error, context _: ProviderFetchContext) -> Bool {
        false
    }
}
