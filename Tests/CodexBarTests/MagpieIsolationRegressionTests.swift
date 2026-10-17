import CodexBarCore
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCLI

@MainActor
struct MagpieIsolationRegressionTests {
    private static let ownedJSON = Data("""
    {"data":[{"provider":"claude","user":"a@example.com","windows":[{"name":"5 hours","used":1}]},
      {"provider":"codex","user":"c@example.com","windows":[{"name":"5 hours","used":1}]},
      {"provider":"grok-plugin","user":"g@example.com","windows":[{"name":"7 days","used":1}]},
      {"provider":"kimi-code","user":"k@example.com","windows":[{"name":"5 hours","used":1}]},
      {"provider":"opencode-go","user":"o@example.com","windows":[{"name":"5 hours","used":1}]}]}
    """.utf8)

    private func makeStore(enabled: Bool, historyStore: PlanUtilizationHistoryStore? = nil) -> UsageStore {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-magpie-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let environment = [
            "HOME": home.path,
            "CODEX_HOME": home.appendingPathComponent(".codex").path,
            "XDG_CONFIG_HOME": home.appendingPathComponent(".config").path,
        ]
        let settings = testSettingsStore(
            suiteName: "MagpieIsolationRegressionTests",
            userDefaults: InMemoryUserDefaults(),
            config: CodexBarConfig(providers: [], magpie: MagpieSourceConfig(enabled: enabled)),
            keychainAccessPolicy: SettingsStoreKeychainAccessPolicy(
                setDisabled: { _ in }, isExplicitlyDisabled: { true }))
        settings.providerDetectionCompleted = true
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        settings._test_codexReconciliationEnvironment = environment
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(homeDirectory: home.path, cacheTTL: 0),
            settings: settings,
            planUtilizationHistoryStore: historyStore,
            startupBehavior: .testing,
            environmentBase: environment)
        settings.setProviderEnabled(provider: .codex, metadata: store.metadata(for: .codex), enabled: true)
        store.magpieTransport = ClaudeMagpieFixture.transport(data: Self.ownedJSON)
        return store
    }

    @Test
    func `codex account scoped refresh reads no codex files while magpie owns codex`() async {
        let store = self.makeStore(enabled: true)
        store.reconcileMagpieSourceConfiguration()
        await store.awaitMagpieRefresh()
        #expect(!store.providerSourceRoute(for: .codex).isNative)
        let spy = MagpieRegressionIOSpy()
        let intercept: @Sendable (NativeProviderIOTestBoundary.Kind) throws -> Void = { kind in
            spy.record(kind)
            throw CancellationError()
        }
        await NativeProviderIOTestBoundary.$intercept.withValue(intercept) {
            await store.refreshCodexAccountScopedState(allowDisabled: true)
        }
        #expect(spy.count(.file) == 0)
    }

    @Test
    func `spend dashboard configuration excludes magpie owned codex`() async {
        let store = self.makeStore(enabled: true)
        store.settings.costUsageEnabled = true
        store.reconcileMagpieSourceConfiguration()
        await store.awaitMagpieRefresh()
        #expect(!store.providerSourceRoute(for: .codex).isNative)
        let spy = MagpieRegressionIOSpy()
        let intercept: @Sendable (NativeProviderIOTestBoundary.Kind) throws -> Void = { kind in
            spy.record(kind)
            throw CancellationError()
        }
        let configuration = NativeProviderIOTestBoundary.$intercept.withValue(intercept) {
            store.settings.invalidateCodexAccountReconciliationSnapshotCache()
            return SpendDashboardSource.configuration(settings: store.settings, store: store)
        }
        #expect(!configuration.providerIDs.contains(UsageProvider.codex.rawValue))
        #expect(spy.count(.file) == 0)
    }

    @Test
    func `empty windows without upstream error show no local error`() async {
        let store = self.makeStore(enabled: true)
        await store.refreshMagpieAccounts()
        store.magpieTransport = ClaudeMagpieFixture.transport(data: Data("""
        {"data":[{"provider":"claude","user":"a@example.com","windows":[{"name":"5 hours","used":1}]},
          {"provider":"codex","user":"c@example.com","windows":[]},
          {"provider":"kimi-code","user":"k@example.com","windows":[{"name":"5 hours","used":1}]},
          {"provider":"opencode-go","user":"o@example.com","windows":[{"name":"5 hours","used":1}]}]}
        """.utf8))
        await store.refreshMagpieAccounts()
        let codex = store.magpieAccountSnapshots.filter { $0.provider.wireID == "codex" }
        #expect(codex.allSatisfy { $0.error == nil })
        #expect(store.magpieLastError == nil)
    }

    private static func historyBuckets(_ percent: Double) -> PlanUtilizationHistoryBuckets {
        PlanUtilizationHistoryBuckets(unscoped: [
            PlanUtilizationSeriesHistory(
                name: .session,
                windowMinutes: 300,
                entries: [
                    PlanUtilizationHistoryEntry(
                        capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                        usedPercent: percent,
                        resetsAt: nil),
                ]),
        ])
    }

    @Test
    func `takeover keeps plan history on disk and shows it again after the switch is off`() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("magpie-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let historyStore = PlanUtilizationHistoryStore(directoryURL: directory)
        historyStore.save([.codex: Self.historyBuckets(20), .claude: Self.historyBuckets(30)])
        let store = self.makeStore(enabled: false, historyStore: historyStore)
        store.planUtilizationHistory = historyStore.load()
        store.planUtilizationHistoryLoaded = true
        store.reconcileMagpieSourceConfiguration()
        #expect(!store.planUtilizationHistory(for: .codex).isEmpty)

        store.settings.magpieSourceEnabled = true
        store.reconcileMagpieSourceConfiguration()
        await store.awaitMagpieRefresh()
        #expect(!store.providerSourceRoute(for: .codex).isNative)
        #expect(store.planUtilizationHistory(for: .codex).isEmpty)

        await store.planUtilizationPersistenceCoordinator.enqueue(store.planUtilizationHistory)
        try await Task.sleep(for: .milliseconds(300))
        let onDisk = historyStore.load()
        #expect(onDisk[.codex] != nil)
        #expect(onDisk[.claude] != nil)

        store.settings.magpieSourceEnabled = false
        store.reconcileMagpieSourceConfiguration()
        #expect(store.providerSourceRoute(for: .codex).isNative)
        #expect(!store.planUtilizationHistory(for: .codex).isEmpty)
    }

    @Test
    func `empty window with upstream error keeps last known usage and shows the error`() async {
        let store = self.makeStore(enabled: true)
        await store.refreshMagpieAccounts()
        store.magpieTransport = ClaudeMagpieFixture.transport(data: Data("""
        {"data":[{"provider":"claude","user":"a@example.com","windows":[{"name":"5 hours","used":1}]},
          {"provider":"codex","user":"c@example.com","windows":[],"error":"upstream timeout"},
          {"provider":"kimi-code","user":"k@example.com","windows":[{"name":"5 hours","used":1}]},
          {"provider":"opencode-go","user":"o@example.com","windows":[{"name":"5 hours","used":1}]}]}
        """.utf8))
        await store.refreshMagpieAccounts()
        let codex = store.magpieAccountSnapshots.filter { $0.provider.wireID == "codex" }
        #expect(codex.count == 1)
        #expect(codex.allSatisfy { !$0.windows.isEmpty && $0.usesLastKnownUsage })
        #expect(codex.allSatisfy { $0.error == "upstream timeout" })
    }

    @Test
    func `hooks watch keys alert state by token account id and falls back to email`() {
        let usage = UsageSnapshot(
            primary: nil,
            secondary: nil,
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                providerID: .claude, accountEmail: "a@example.com", accountOrganization: nil, loginMethod: nil))
        let id = UUID()
        #expect(CodexBarCLI.hooksWatchAccountDiscriminator(
            tokenAccountID: id, usage: usage, provider: .claude) == id.uuidString)
        #expect(CodexBarCLI.hooksWatchAccountDiscriminator(
            tokenAccountID: nil, usage: usage, provider: .claude) == "a@example.com")
    }

    @Test
    func `in flight codex credits do not publish after magpie takes codex`() async {
        let store = self.makeStore(enabled: false)
        store.settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "c@example.com",
            workspaceAccountID: nil,
            codexHomePath: "/Users/test/.codex",
            observedAt: Date(),
            identity: .unresolved)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 1, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date(),
                identity: ProviderIdentitySnapshot(
                    providerID: .codex, accountEmail: "c@example.com", accountOrganization: nil, loginMethod: "Pro")),
            provider: .codex)
        store.reconcileMagpieSourceConfiguration()
        let gate = MagpieRegressionGate()
        store._test_codexCreditsLoaderOverride = {
            await gate.enterAndWait()
            return CreditsSnapshot(remaining: 7, events: [], updatedAt: Date())
        }
        let task = Task { @MainActor in await store.refreshCreditsIfNeeded() }
        await gate.waitUntilEntered()
        store.settings.magpieSourceEnabled = true
        store.reconcileMagpieSourceConfiguration()
        await store.awaitMagpieRefresh()
        #expect(!store.providerSourceRoute(for: .codex).isNative)
        await gate.release()
        await task.value
        #expect(store.credits == nil)
    }

    @Test
    func `late dashboard results do not publish after magpie takes codex`() async {
        let store = self.makeStore(enabled: true)
        store.reconcileMagpieSourceConfiguration()
        await store.awaitMagpieRefresh()
        #expect(!store.providerSourceRoute(for: .codex).isNative)
        let magpieSnapshot = store.snapshots[.codex]
        let dashboard = OpenAIDashboardSnapshot(
            signedInEmail: "c@example.com",
            codeReviewRemainingPercent: 88,
            creditEvents: [],
            dailyBreakdown: [],
            usageBreakdown: [],
            creditsPurchaseURL: nil,
            primaryLimit: RateWindow(usedPercent: 77, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondaryLimit: nil,
            creditsRemaining: 5,
            accountPlan: "Pro",
            updatedAt: Date())
        let applied = await store.applyOpenAIDashboard(dashboard, targetEmail: "c@example.com")
        await store.applyOpenAIDashboardFailure(message: "late failure")
        await store.applyOpenAIDashboardLoginRequiredFailure()
        #expect(applied == false)
        #expect(store.openAIDashboard == nil)
        #expect(store.lastOpenAIDashboardError == nil)
        #expect(store.openAIDashboardRequiresLogin == false)
        #expect(store.snapshots[.codex]?.primary?.usedPercent == magpieSnapshot?.primary?.usedPercent)
        #expect(store.snapshots[.codex]?.primary?.usedPercent != 77)
    }

    @Test(arguments: [UsageProvider.claude, .codex, .grok, .kimi, .opencodego])
    func `hooks watch observation does no native IO while magpie is on`(provider: UsageProvider) async {
        // Unreachable gateway: first-discovery failure, so every mapped provider stays non-native.
        let config = CodexBarConfig(
            providers: [ProviderConfig(id: provider.instanceID)],
            magpie: MagpieSourceConfig(enabled: true, quotasURL: "http://127.0.0.1:9/v1/magpie/quotas"))
        let spy = MagpieRegressionIOSpy()
        let intercept: @Sendable (NativeProviderIOTestBoundary.Kind) throws -> Void = { kind in
            spy.record(kind)
            throw CancellationError()
        }
        _ = await NativeProviderIOTestBoundary.$intercept.withValue(intercept) {
            await CodexBarCLI.hooksWatchObservation(provider: provider, config: config, verbose: false, webTimeout: 5)
        }
        for kind in NativeProviderIOTestBoundary.Kind.allCases {
            #expect(spy.count(kind) == 0, "\(provider.rawValue) \(kind.rawValue)")
        }
    }

    @Test
    func `hooks watch observation reaches native IO when magpie is off`() async {
        let config = CodexBarConfig(providers: [ProviderConfig(id: UsageProvider.codex.instanceID)])
        let spy = MagpieRegressionIOSpy()
        let intercept: @Sendable (NativeProviderIOTestBoundary.Kind) throws -> Void = { kind in
            spy.record(kind)
            throw CancellationError()
        }
        _ = await NativeProviderIOTestBoundary.$intercept.withValue(intercept) {
            await CodexBarCLI.hooksWatchObservation(provider: .codex, config: config, verbose: false, webTimeout: 5)
        }
        let total = NativeProviderIOTestBoundary.Kind.allCases.reduce(0) { $0 + spy.count($1) }
        #expect(total > 0)
    }
}

private final class MagpieRegressionIOSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [NativeProviderIOTestBoundary.Kind: Int] = [:]

    func record(_ kind: NativeProviderIOTestBoundary.Kind) {
        self.lock.withLock { self.counts[kind, default: 0] += 1 }
    }

    func count(_ kind: NativeProviderIOTestBoundary.Kind) -> Int {
        self.lock.withLock { self.counts[kind, default: 0] }
    }
}

private actor MagpieRegressionGate {
    private var entered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?
    private var released = false

    func enterAndWait() async {
        self.entered = true
        for waiter in self.enteredWaiters {
            waiter.resume()
        }
        self.enteredWaiters = []
        if self.released { return }
        await withCheckedContinuation { self.releaseWaiter = $0 }
    }

    func waitUntilEntered() async {
        if self.entered { return }
        await withCheckedContinuation { self.enteredWaiters.append($0) }
    }

    func release() {
        self.released = true
        self.releaseWaiter?.resume()
        self.releaseWaiter = nil
    }
}
