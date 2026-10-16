import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct MagpieIsolationRegressionTests {
    private static let ownedJSON = Data("""
    {"data":[{"provider":"claude","user":"a@example.com","windows":[{"name":"5 hours","used":1}]},
      {"provider":"codex","user":"c@example.com","windows":[{"name":"5 hours","used":1}]},
      {"provider":"kimi-code","user":"k@example.com","windows":[{"name":"5 hours","used":1}]},
      {"provider":"opencode-go","user":"o@example.com","windows":[{"name":"5 hours","used":1}]}]}
    """.utf8)

    private func makeStore(enabled: Bool) -> UsageStore {
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
