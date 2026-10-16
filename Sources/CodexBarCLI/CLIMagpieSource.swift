import CodexBarCore
import Foundation

actor CLIMagpieSource {
    private var task: Task<[MagpieQuotaRow], Error>?
    private var completedAt: Date?
    private var ownedWireIDs: Set<String> = []
    private let transport: MagpieQuotasReader.Transport

    init(transport: @escaping MagpieQuotasReader.Transport = MagpieQuotasReader.urlSessionTransport) {
        self.transport = transport
    }

    func owns(_ wireID: String) -> Bool {
        self.ownedWireIDs.contains(wireID)
    }

    func rows(quotasURL: String?) async throws -> [MagpieQuotaRow] {
        if let completedAt, Date().timeIntervalSince(completedAt) > 1 {
            self.task = nil
            self.completedAt = nil
        }
        if let task { return try await task.value }
        let transport = self.transport
        let task = Task { try await MagpieQuotasReader.readRows(quotasURL: quotasURL, transport: transport) }
        self.task = task
        do {
            let rows = try await task.value
            self.ownedWireIDs.formUnion(rows.map(\.provider))
            self.completedAt = Date()
            return rows
        } catch {
            self.completedAt = Date()
            throw error
        }
    }
}

extension CodexBarCLI {
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
