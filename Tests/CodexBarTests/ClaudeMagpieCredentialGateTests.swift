import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

/// Claude settings snapshots carry magpie ownership from the config, and the Claude fetch pipeline then resolves
/// only the magpie strategy regardless of source mode or selected token account.
struct ClaudeMagpieCredentialGateTests {
    @Test
    func `CLI settings snapshot carries magpie ownership from the config`() throws {
        var claude = ProviderConfig(id: .claude)
        claude.claudeMagpieEnabled = true
        let tokenContext = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
            config: CodexBarConfig(providers: [claude]),
            verbose: false)

        let settings = try #require(tokenContext.settingsSnapshot(for: .claude, account: nil)?.claude)

        #expect(settings.magpieQuotasURL != nil)
    }

    @Test
    func `CLI settings snapshot has no magpie ownership when it is off`() throws {
        let tokenContext = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
            config: CodexBarConfig(providers: [ProviderConfig(id: .claude)]),
            verbose: false)

        #expect(tokenContext.settingsSnapshot(for: .claude, account: nil)?.claude?.magpieQuotasURL == nil)
    }

    @Test(arguments: [
        (ProviderSourceMode.auto, false),
        (ProviderSourceMode.oauth, false),
        (ProviderSourceMode.web, false),
        (ProviderSourceMode.cli, false),
        (ProviderSourceMode.api, false),
        (ProviderSourceMode.auto, true),
        (ProviderSourceMode.oauth, true),
    ])
    func `magpie ownership resolves only the magpie strategy`(sourceMode: ProviderSourceMode, selected: Bool) async {
        let context = Self.context(sourceMode: sourceMode, magpieQuotasURL: "", selected: selected)
        let strategies = await ClaudeProviderDescriptor.descriptor.fetchPlan.pipeline.resolveStrategies(context)

        #expect(strategies.map(\.id) == ["claude.magpie"])
    }

    @Test
    func `without magpie the credential strategies are unchanged`() async {
        let context = Self.context(sourceMode: .oauth, magpieQuotasURL: nil, selected: false)
        let strategies = await ClaudeProviderDescriptor.descriptor.fetchPlan.pipeline.resolveStrategies(context)

        #expect(!strategies.map(\.id).contains("claude.magpie"))
    }

    @Test
    func `magpie strategy reports the active account and never falls back`() async throws {
        let strategy = ClaudeMagpieFetchStrategy(quotasURL: "", transport: ClaudeMagpieFixture.transport())
        let context = Self.context(sourceMode: .auto, magpieQuotasURL: "", selected: false)

        let result = try await strategy.fetch(context)

        #expect(result.usage.secondary?.usedPercent == 84)
        #expect(result.sourceLabel == "magpie")
        #expect(!strategy.shouldFallback(on: ClaudeMagpieAccountReaderError.httpStatus(500), context: context))
    }

    @Test
    func `token accounts are not resolved for Claude under magpie`() throws {
        for allAccounts in [false, true] {
            let tokenContext = try TokenAccountCLIContext(
                selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: allAccounts),
                config: Self.configWithTwoTokenAccounts(),
                verbose: false)
            #expect(try tokenContext.resolvedAccounts(for: .claude).isEmpty)
        }
    }

    @Test
    func `serve does not expand Claude token accounts under magpie`() {
        #expect(!CodexBarCLI.serveIncludesConfiguredAccounts(
            provider: .claude,
            config: Self.configWithTwoTokenAccounts(),
            allAccounts: true))
    }

    @Test
    func `cookie refresh is skipped for Claude under magpie`() async throws {
        let tokenContext = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
            config: Self.configWithTwoTokenAccounts(),
            verbose: false)

        let result = await CodexBarCLI.refreshCookie(
            descriptor: ClaudeProviderDescriptor.descriptor,
            tokenContext: tokenContext,
            browserDetection: BrowserDetection(cacheTTL: 0))

        #expect(result.status == .skipped)
    }

    private static func configWithTwoTokenAccounts() -> CodexBarConfig {
        var claude = ProviderConfig(
            id: .claude,
            enabled: true,
            tokenAccounts: ProviderTokenAccountData(
                version: 1,
                accounts: [
                    ProviderTokenAccount(id: UUID(), label: "One", token: "sk-ant-oat-one", addedAt: 1, lastUsed: 2),
                    ProviderTokenAccount(id: UUID(), label: "Two", token: "sk-ant-oat-two", addedAt: 1, lastUsed: 2),
                ],
                activeIndex: 0))
        claude.claudeMagpieEnabled = true
        return CodexBarConfig(providers: [claude])
    }

    private static func context(
        sourceMode: ProviderSourceMode,
        magpieQuotasURL: String?,
        selected: Bool) -> ProviderFetchContext
    {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let settings = ProviderSettingsSnapshot.make(claude: ClaudeProviderSettings(
            usageDataSource: .auto,
            webExtrasEnabled: false,
            cookieSource: .off,
            manualCookieHeader: nil,
            magpieQuotasURL: magpieQuotasURL))
        return ProviderFetchContext(
            runtime: .cli,
            sourceMode: sourceMode,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: [:],
            settings: settings,
            fetcher: UsageFetcher(environment: [:]),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection,
            selectedTokenAccountID: selected ? UUID() : nil)
    }
}
