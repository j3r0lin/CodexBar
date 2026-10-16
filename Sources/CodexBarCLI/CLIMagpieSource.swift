import CodexBarCore
import Foundation

actor CLIMagpieSource {
    private var task: Task<[MagpieQuotaRow], Error>?
    private var ownedWireIDs: Set<String> = []
    private let transport: MagpieQuotasReader.Transport

    init(
        transport: @escaping MagpieQuotasReader.Transport = MagpieQuotasReader.urlSessionTransport,
        ownedWireIDs: Set<String>? = nil)
    {
        self.ownedWireIDs = ownedWireIDs ?? Set(
            CodexBarCLI.valueFromAppDefaults("magpieTakeoverProviderIDs") as [String]? ?? [])
        self.transport = transport
    }

    func owns(_ wireID: String) -> Bool {
        self.ownedWireIDs.contains(wireID)
    }

    func route(for provider: UsageProvider, configuration: MagpieSourceConfig?) async -> ProviderSourceRoute {
        guard configuration?.enabled == true else { return .native }
        var discoverySucceeded = false
        do {
            let rows = try await self.rows(quotasURL: configuration?.quotasURL)
            self.ownedWireIDs.formUnion(rows.map(\.provider))
            discoverySucceeded = true
        } catch {}
        return ProviderSourceRoute.resolve(
            provider: provider,
            enabled: true,
            ownedWireIDs: self.ownedWireIDs,
            discoverySucceeded: discoverySucceeded)
    }

    func rows(quotasURL: String?) async throws -> [MagpieQuotaRow] {
        if let task { return try await task.value }
        let transport = self.transport
        let task = Task { try await MagpieQuotasReader.readRows(quotasURL: quotasURL, transport: transport) }
        self.task = task
        do {
            let rows = try await task.value
            self.ownedWireIDs.formUnion(rows.map(\.provider))
            return rows
        } catch {
            throw error
        }
    }
}

extension CodexBarCLI {
    static func fetchRoutedProviderUsage(
        provider: UsageProvider,
        tokenContext: TokenAccountCLIContext,
        native: () async -> ProviderFetchOutcome) async -> ProviderFetchOutcome
    {
        let route = await tokenContext.magpieSource.route(for: provider, configuration: tokenContext.config.magpie)
        guard !route.isNative else { return await native() }
        do {
            let rows = try await tokenContext.magpieSource.rows(quotasURL: tokenContext.config.magpie?.quotasURL)
            let accounts = MagpieAccountProjection.snapshots(from: rows)
            guard let account = accounts.first(where: { $0.provider.nativeProvider == provider && $0.isActive }),
                  let usage = MagpieUsageProjection.usageSnapshot(for: account)
            else { throw UsageError.noRateLimitsFound }
            return ProviderFetchOutcome(result: .success(ProviderFetchResult(
                usage: usage, credits: nil, dashboard: nil, sourceLabel: "magpie",
                strategyID: "magpie", strategyKind: .web)), attempts: [])
        } catch {
            return ProviderFetchOutcome(result: .failure(error), attempts: [])
        }
    }

    static func fetchMagpieUsageIfOwned(
        provider: UsageProvider,
        status: ProviderStatusPayload?,
        tokenContext: TokenAccountCLIContext,
        command: UsageCommandContext) async -> UsageCommandOutput?
    {
        guard tokenContext.config.magpie?.enabled == true,
              let wireID = MagpieProviderMapping.wireID(for: provider)
        else { return nil }
        var output = UsageCommandOutput()
        do {
            let rows = try await tokenContext.magpieSource.rows(quotasURL: tokenContext.config.magpie?.quotasURL)
            let previouslyOwned = await tokenContext.magpieSource.owns(wireID)
            guard rows.contains(where: { $0.provider == wireID }) || previouslyOwned else { return nil }
            let accounts = MagpieUsageProjection.providerAccountSnapshots(
                for: provider, in: MagpieAccountProjection.snapshots(from: rows))
            for account in accounts {
                guard let usage = account.snapshot else { continue }
                if command.format == .json {
                    output.payload.append(ProviderPayload(
                        provider: provider,
                        account: account.displayLabel,
                        version: nil,
                        source: "magpie",
                        status: status,
                        usage: usage,
                        credits: nil,
                        antigravityPlanInfo: nil,
                        openaiDashboard: nil,
                        error: nil))
                } else if command.cardsLayout {
                    output.cards.append(CLICardsRenderer.makeCard(CLICardBuildInput(
                        provider: provider,
                        snapshot: usage,
                        credits: nil,
                        source: "magpie",
                        status: status,
                        notes: [],
                        useColor: command.useColor,
                        resetStyle: command.resetStyle,
                        weeklyWorkDays: command.weeklyWorkDays,
                        now: Date())))
                } else {
                    output.sections.append(CLIRenderer.renderText(
                        provider: provider,
                        snapshot: usage,
                        credits: nil,
                        context: RenderContext(
                            header: "\(provider.rawValue) · magpie",
                            status: status,
                            useColor: command.useColor,
                            resetStyle: command.resetStyle,
                            weeklyWorkDays: command.weeklyWorkDays)))
                }
            }
        } catch {
            output.exitCode = .failure
            output.payload.append(Self.makeProviderErrorPayload(
                provider: provider, account: nil, source: "magpie", status: status, error: error))
            output.cardFailures.append(CLICardFailure(
                provider: provider, accountLabel: nil, message: error.localizedDescription))
        }
        return output
    }
}
