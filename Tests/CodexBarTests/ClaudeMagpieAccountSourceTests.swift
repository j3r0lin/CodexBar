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
        // Retained numbers are last-known: the age-less menu bar must not present them as current.
        #expect(store.claudeMagpieAccountSnapshots.allSatisfy { $0.snapshot == nil || $0.usesLastKnownUsage })
        #expect(store.claudeMagpieAccountSnapshots.allSatisfy { $0.error != nil })
        #expect(store.menuBarSnapshot(for: UsageProvider.claude.instanceID) == nil)
    }

    @Test
    func `hide personal info labels magpie accounts by gateway ordinal`() async throws {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-privacy")
        store.settings.claudeMagpieEnabled = true
        await store.refreshClaudeMagpieAccounts()

        let aliased = try #require(store.claudeMagpieAccountSnapshots.first { $0.displayLabel == "main" })
        #expect(ClaudeSwapAccountMenuDisplay.label(for: aliased, hidePersonalInfo: true) == "Account 1")
        let help = ClaudeSwapAccountMenuDisplay.chipHelp(for: aliased, hidePersonalInfo: true)
        #expect(!help.contains("main") && !help.contains("Example Org") && !help.contains("@"))
        #expect(ClaudeSwapAccountMenuDisplay.label(for: aliased, hidePersonalInfo: false) == "main")
    }

    @Test
    func `turning magpie on retires credential derived widget usage`() {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-widget-retire")
        store._setSnapshotForTesting(Self.ambientSnapshot(), provider: .claude)
        store.lastKnownResetSnapshots[.claude] = Self.ambientSnapshot()
        store.widgetUsagePreservationBlockedProviders.remove(.claude)

        store.settings.claudeMagpieEnabled = true
        ClaudeProviderRuntime().settingsDidChange(
            context: ProviderRuntimeContext(provider: .claude, settings: store.settings, store: store))
        store.claudeMagpieRefreshTask?.cancel()

        #expect(store.snapshot(for: .claude) == nil)
        #expect(store.lastKnownResetSnapshots[.claude] == nil)
        #expect(store.widgetUsagePreservationBlockedProviders.contains(.claude))
    }

    @Test
    func `turning magpie off clears its accounts and runs a normal Claude refresh`() async {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-off")
        let runtime = ClaudeProviderRuntime()
        let context = ProviderRuntimeContext(provider: .claude, settings: store.settings, store: store)
        store.settings.claudeMagpieEnabled = true
        runtime.settingsDidChange(context: context)
        await store.claudeMagpieRefreshTask?.value
        #expect(store.claudeMagpieAccountSnapshots.count == 3)
        let refreshed = RefreshRecorder()
        store._test_providerRefreshOverride = { provider in await refreshed.record(provider) }

        store.settings.claudeMagpieEnabled = false
        runtime.settingsDidChange(context: context)

        #expect(store.claudeMagpieAccountSnapshots.isEmpty)
        #expect(store.claudeMagpieLastRefreshAt == nil)
        #expect(await refreshed.firstProvider() == .claude)
    }

    @Test
    func `starting with magpie on reads magpie without the ambient fetch`() async throws {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-start")
        let recorder = AmbientFetchRecorder()
        let baseSpec = try #require(store.providerSpecs[.claude])
        store.providerSpecs[.claude] = Self.recordingSpec(baseSpec: baseSpec, recorder: recorder)
        store.settings.claudeMagpieEnabled = true

        ClaudeProviderRuntime().start(
            context: ProviderRuntimeContext(provider: .claude, settings: store.settings, store: store))
        await store.claudeMagpieRefreshTask?.value
        await store.refreshProvider(.claude)
        await store.claudeMagpieRefreshTask?.value

        #expect(await recorder.count < 1)
        #expect(store.claudeMagpieAccountSnapshots.count == 3)
    }

    @Test
    func `Claude Code sign in and Keychain actions are hidden under magpie`() {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-login")
        store.settings.claudeMagpieEnabled = true
        for hasAccount in [false, true] {
            let action = ClaudeProviderImplementation().loginMenuAction(context: ProviderMenuLoginContext(
                provider: .claude,
                store: store,
                settings: store.settings,
                account: AccountInfo(email: nil, plan: nil),
                hasAccount: hasAccount))
            #expect(action == nil)
        }
    }

    @Test
    func `a result for a replaced URL is discarded`() async {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-url")
        store.settings.claudeMagpieEnabled = true
        let settings = store.settings
        let base = ClaudeMagpieFixture.transport()
        store.claudeMagpieTransport = { request in
            await MainActor.run { settings.claudeMagpieQuotasURL = "http://127.0.0.1:9/v1/magpie/quotas" }
            return try await base(request)
        }

        await store.refreshClaudeMagpieAccounts()

        #expect(store.claudeMagpieAccountSnapshots.isEmpty)
        #expect(store.claudeMagpieLastRefreshAt == nil)
    }

    @Test
    func `debug log under magpie reports magpie ownership instead of probing credentials`() async {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-debug")
        store.settings.claudeMagpieEnabled = true

        let log = await store.debugLog(for: .claude)

        #expect(log.contains("magpie owns Claude accounts"))
        #expect(log.contains(ClaudeMagpieAccountReader.defaultQuotasURL))
    }

    @Test
    func `widget does not show last known magpie usage as current`() async {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-widget-last-known")
        store.settings.claudeMagpieEnabled = true
        await store.refreshClaudeMagpieAccounts()
        store.claudeMagpieTransport = ClaudeMagpieFixture.transport(status: 500)
        await store.refreshClaudeMagpieAccounts()
        var saved: WidgetSnapshot?
        store._test_widgetSnapshotSaveOverride = { saved = $0 }
        defer { store._test_widgetSnapshotSaveOverride = nil }

        store.persistWidgetSnapshot(reason: "magpie-last-known")
        await store.widgetSnapshotPersistTask?.value

        let claude = saved?.entries.first { $0.provider == .claude }
        #expect(claude?.secondary?.usedPercent != 84)
    }

    @Test
    func `turning magpie on keeps the local log token cost`() {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-token-cost")
        store._setTokenSnapshotForTesting(
            CostUsageTokenSnapshot(
                sessionTokens: 10,
                sessionCostUSD: 1,
                last30DaysTokens: 10,
                last30DaysCostUSD: 1,
                daily: []),
            provider: .claude)

        store.settings.claudeMagpieEnabled = true
        ClaudeProviderRuntime().settingsDidChange(
            context: ProviderRuntimeContext(provider: .claude, settings: store.settings, store: store))
        store.claudeMagpieRefreshTask?.cancel()

        #expect(store.tokenSnapshot(for: .claude) != nil)
    }

    @Test
    func `app settings snapshot carries the magpie URL only while magpie is on`() {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-settings-snapshot")
        #expect(store.settings.claudeSettingsSnapshot(tokenOverride: nil).magpieQuotasURL == nil)

        store.settings.claudeMagpieEnabled = true
        store.settings.claudeMagpieQuotasURL = "http://127.0.0.1:4000/v1/magpie/quotas"

        #expect(store.settings.claudeSettingsSnapshot(tokenOverride: nil).magpieQuotasURL ==
            "http://127.0.0.1:4000/v1/magpie/quotas")
    }

    @Test
    func `a result from a stale refresh generation is discarded`() async {
        let store = Self.makeStore(suite: "ClaudeMagpieAccountSourceTests-generation")
        store.settings.claudeMagpieEnabled = true

        await store.refreshClaudeMagpieAccounts(generation: UInt64.max)

        #expect(store.claudeMagpieAccountSnapshots.isEmpty)
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
        #expect(ClaudeAccountSource.widgetLabel(for: active, in: store.claudeAccountSource.accounts) == "Account 2")
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

    private static func ambientSnapshot() -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(usedPercent: 99, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
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

private actor RefreshRecorder {
    private var first: UsageProvider?
    private var waiters: [CheckedContinuation<UsageProvider, Never>] = []

    func record(_ provider: UsageProvider) {
        guard self.first == nil else { return }
        self.first = provider
        for waiter in self.waiters {
            waiter.resume(returning: provider)
        }
        self.waiters = []
    }

    func firstProvider() async -> UsageProvider {
        if let first { return first }
        return await withCheckedContinuation { self.waiters.append($0) }
    }
}
