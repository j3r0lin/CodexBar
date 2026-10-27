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
            self.ownedWireIDs.formUnion(rows.map { MagpieProviderMapping.ownedWireID(for: $0.provider) })
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
            self.ownedWireIDs.formUnion(rows.map { MagpieProviderMapping.ownedWireID(for: $0.provider) })
            return rows
        } catch {
            throw error
        }
    }
}

extension CodexBarCLI {
    /// A Claude-family provider suspended by the magpie switch answers with this instead of
    /// falling through to native reads.
    struct MagpieSuspendedProviderError: LocalizedError {
        let provider: UsageProvider

        var errorDescription: String? {
            ProviderSourceRoute.suspendedMessage(for: self.provider)
        }
    }

    /// An error magpie reported for an account row, shown as-is.
    struct MagpieUpstreamError: LocalizedError {
        let message: String

        var errorDescription: String? {
            self.message
        }
    }

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
            let result = ProviderFetchResult(
                usage: usage,
                credits: nil,
                dashboard: nil,
                sourceLabel: "magpie",
                strategyID: "magpie",
                strategyKind: .web)
            return ProviderFetchOutcome(result: .success(result), attempts: [])
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
        guard tokenContext.config.magpie?.enabled == true else { return nil }
        let wireIDs = MagpieProviderMapping.wireIDs(for: provider)
        // Claude-family providers never fall through to native reads while the switch is on,
        // even without a wire ID or any magpie rows (`--provider all` expands to them too).
        let switchSuspended = ProviderSourceRoute.switchOnNativeForbidden.contains(provider)
        guard !wireIDs.isEmpty || switchSuspended else { return nil }
        var output = UsageCommandOutput()
        do {
            let rows = try await tokenContext.magpieSource.rows(quotasURL: tokenContext.config.magpie?.quotasURL)
            let listsProvider = rows.contains { wireIDs.contains(MagpieProviderMapping.ownedWireID(for: $0.provider)) }
            var previouslyOwned = false
            for wireID in wireIDs where await tokenContext.magpieSource.owns(wireID) {
                previouslyOwned = true
                break
            }
            guard listsProvider || previouslyOwned || switchSuspended
            else { return nil }
            let accounts = MagpieUsageProjection.providerAccountSnapshots(
                for: provider, in: MagpieAccountProjection.snapshots(from: rows))
            var emitted = false
            for account in accounts {
                guard let usage = account.snapshot else { continue }
                emitted = true
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
            if !emitted, switchSuspended {
                if listsProvider {
                    // Rows with empty windows are an empty result; only an upstream error is
                    // reported, matching the app. Nothing here may touch native reads.
                    for account in accounts {
                        guard let message = account.error else { continue }
                        let error = MagpieUpstreamError(message: message)
                        output.exitCode = .failure
                        output.payload.append(Self.makeProviderErrorPayload(
                            provider: provider,
                            account: account.displayLabel,
                            source: "magpie",
                            status: status,
                            error: error))
                        output.cardFailures.append(CLICardFailure(
                            provider: provider,
                            accountLabel: account.displayLabel,
                            message: message))
                    }
                } else {
                    // No rows at all: the suspended state answers, so the caller never continues
                    // into a native credential, cookie, or Keychain read.
                    let error = MagpieSuspendedProviderError(provider: provider)
                    output.exitCode = .failure
                    output.payload.append(Self.makeProviderErrorPayload(
                        provider: provider, account: nil, source: "magpie", status: status, error: error))
                    output.cardFailures.append(CLICardFailure(
                        provider: provider, accountLabel: nil, message: error.localizedDescription))
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
