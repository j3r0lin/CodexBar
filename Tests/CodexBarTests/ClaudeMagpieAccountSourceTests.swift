import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct ClaudeMagpieAccountSourceTests {
    @Test
    func `magpie accounts drive cards and the menu bar from the last served account`() async throws {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-cards")
        store.settings.claudeMagpieEnabled = true

        await store.refreshClaudeMagpieAccounts()

        let source = store.claudeAccountSource
        #expect(source.accounts.count == 3)
        #expect(source.ownsPresentation)
        #expect(source.activeAccount?.accountEmail == "second@example.com")
        let bar = try #require(store.menuBarSnapshot(for: UsageProvider.claude.instanceID))
        #expect(bar.secondary?.usedPercent == 84)
    }

    @Test
    func `a single magpie account still owns the Claude presentation`() async {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-single")
        store.settings.claudeMagpieEnabled = true
        let json = #"{"data":[{"provider":"claude","user":"solo@example.com","#
            + #""windows":[{"name":"5 hours","used":7}]}]}"#
        store.claudeMagpieTransport = ClaudeMagpieFixture.transport(data: Data(json.utf8))

        await store.refreshClaudeMagpieAccounts()

        #expect(store.claudeAccountSource.ownsPresentation)
        #expect(store.menuBarSnapshot(for: UsageProvider.claude.instanceID)?.primary?.usedPercent == 7)
    }

    @Test
    func `a failed refresh keeps the last accounts and reports the error`() async {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-failure")
        store.settings.claudeMagpieEnabled = true
        await store.refreshClaudeMagpieAccounts()

        store.claudeMagpieTransport = ClaudeMagpieFixture.transport(status: 500)
        await store.refreshClaudeMagpieAccounts()

        #expect(store.claudeMagpieAccountSnapshots.count == 3)
        #expect(store.claudeMagpieLastError != nil)
    }

    @Test
    func `magpie hides claude-swap accounts and stops the adapter`() {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-swap")
        store.settings.claudeSwapExecutablePath = "/path/to/cswap"
        store.settings.claudeSwapEnabled = true
        store.claudeSwapAccountSnapshots = [Self.swapAccount(number: 1), Self.swapAccount(number: 2)]
        #expect(store.shouldFetchClaudeSwapAccounts())

        store.settings.claudeMagpieEnabled = true
        ClaudeProviderRuntime().settingsDidChange(
            context: ProviderRuntimeContext(provider: .claude, settings: store.settings, store: store))

        #expect(!store.shouldFetchClaudeSwapAccounts())
        #expect(store.claudeSwapRefreshTask == nil)
        #expect(store.claudeSwapAccountSnapshots.isEmpty)
        #expect(store.claudeAccountSource.accounts.allSatisfy { $0.id.source == "magpie" })
        store.claudeMagpieRefreshTask?.cancel()
    }

    @Test
    func `Claude refresh under magpie never runs the ambient fetch`() async throws {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-ambient")
        let recorder = AmbientFetchRecorder()
        let baseSpec = try #require(store.providerSpecs[.claude])
        store.providerSpecs[.claude] = Self.recordingSpec(baseSpec: baseSpec, recorder: recorder)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 99, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .claude)
        store.settings.claudeMagpieEnabled = true
        ClaudeProviderRuntime().settingsDidChange(
            context: ProviderRuntimeContext(provider: .claude, settings: store.settings, store: store))

        await store.refreshProvider(.claude)
        await store.claudeMagpieRefreshTask?.value

        #expect(await recorder.count < 1)
        #expect(store.snapshot(for: .claude) == nil)
        #expect(store.claudeMagpieAccountSnapshots.count == 3)
    }

    @Test
    func `widget identities for magpie accounts do not contain the email`() async throws {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-widget")
        store.settings.claudeMagpieEnabled = true
        await store.refreshClaudeMagpieAccounts()

        let active = try #require(store.claudeAccountSource.activeAccount)
        let key = try #require(ClaudeAccountSource.widgetOwnerKey(for: active))
        #expect(!key.contains("@"))
        #expect(ClaudeAccountSource.widgetLabel(for: active, in: store.claudeAccountSource.accounts) == "Account 1")
    }

    // MARK: - Helpers

    private static func makeStore(suite: String) -> UsageStore {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore(),
            codexCookieStore: InMemoryCookieHeaderStore(),
            claudeCookieStore: InMemoryCookieHeaderStore(),
            cursorCookieStore: InMemoryCookieHeaderStore(),
            opencodeCookieStore: InMemoryCookieHeaderStore(),
            factoryCookieStore: InMemoryCookieHeaderStore(),
            minimaxCookieStore: InMemoryMiniMaxCookieStore(),
            minimaxAPITokenStore: InMemoryMiniMaxAPITokenStore(),
            kimiTokenStore: InMemoryKimiTokenStore(),
            augmentCookieStore: InMemoryCookieHeaderStore(),
            ampCookieStore: InMemoryCookieHeaderStore(),
            copilotTokenStore: InMemoryCopilotTokenStore(),
            tokenAccountStore: InMemoryTokenAccountStore())
        settings.providerDetectionCompleted = true
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        if let metadata = ProviderRegistry.shared.metadata[.claude] {
            settings.setProviderEnabled(provider: .claude, metadata: metadata, enabled: true)
        }
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            environmentBase: [:])
        store.claudeMagpieTransport = ClaudeMagpieFixture.transport()
        return store
    }

    private static func swapAccount(number: Int) -> ProviderAccountUsageSnapshot {
        ProviderAccountUsageSnapshot(
            id: ProviderAccountIdentity(source: ClaudeSwapAccountProjection.sourceName, opaqueID: String(number)),
            provider: .claude,
            displayLabel: "swap\(number)@example.com",
            isActive: number == 1,
            snapshot: nil,
            error: nil,
            sourceLabel: ClaudeSwapAccountProjection.sourceLabel)
    }

    private static func recordingSpec(baseSpec: ProviderSpec, recorder: AmbientFetchRecorder) -> ProviderSpec {
        let base = baseSpec.descriptor
        let descriptor = ProviderDescriptor(
            id: .claude,
            metadata: base.metadata,
            branding: base.branding,
            tokenCost: base.tokenCost,
            fetchPlan: ProviderFetchPlan(
                sourceModes: base.fetchPlan.sourceModes,
                pipeline: ProviderFetchPipeline { _ in
                    await recorder.record()
                    return []
                }),
            cli: base.cli)
        return ProviderSpec(
            style: baseSpec.style,
            isEnabled: baseSpec.isEnabled,
            descriptor: descriptor,
            makeFetchContext: baseSpec.makeFetchContext)
    }
}

private actor AmbientFetchRecorder {
    private(set) var count = 0

    func record() {
        self.count += 1
    }
}
