import Foundation
import Security
import Testing
@testable import CodexBar
@testable import CodexBarCore

@MainActor
struct MagpieSourceTransitionTests {
    private func makeStore() -> UsageStore {
        let settings = testSettingsStore(
            suiteName: "MagpieSourceTransitionTests",
            userDefaults: InMemoryUserDefaults(),
            config: CodexBarConfig(providers: [], magpie: MagpieSourceConfig(enabled: true)),
            keychainAccessPolicy: SettingsStoreKeychainAccessPolicy(
                setDisabled: { _ in }, isExplicitlyDisabled: { true }))
        settings.providerDetectionCompleted = true
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        store.magpieTransport = ClaudeMagpieFixture.transport()
        return store
    }

    @Test(arguments: ["enabling", "firstFailure", "laterFailure", "disappeared"])
    func `native refresh dispatch stays closed across discovery outcomes`(state: String) async {
        let store = self.makeStore()
        let managed: [UsageProvider] = [.claude, .codex, .kimi, .opencodego]
        var nativeDispatches: [UsageProvider] = []
        store._test_providerRefreshOverride = { nativeDispatches.append($0) }
        store.magpieTransport = ClaudeMagpieFixture.transport(data: Data("""
        {"data":[{"provider":"claude","windows":[]},{"provider":"codex","windows":[]},
          {"provider":"kimi-code","windows":[]},{"provider":"opencode-go","windows":[]}]}
        """.utf8))
        switch state {
        case "firstFailure":
            store.magpieTransport = ClaudeMagpieFixture.transport(status: 503)
        case "laterFailure", "disappeared":
            store.reconcileMagpieSourceConfiguration()
            await store.refreshMagpieAccounts()
            store.magpieTransport = state == "laterFailure"
                ? ClaudeMagpieFixture.transport(status: 503)
                : ClaudeMagpieFixture.transport(data: Data(#"{"data":[]}"#.utf8))
            await store.refreshMagpieAccounts()
        default:
            break
        }
        for provider in managed {
            await store.refreshProvider(provider, allowDisabled: true)
            #expect(!store.providerSourceRoute(for: provider).isNative)
        }
        #expect(nativeDispatches.isEmpty)
    }

    @Test(arguments: ["enabling", "firstFailure", "laterFailure", "disappeared"])
    func `managed refresh performs no sensitive native IO before context construction`(state: String) async {
        let store = self.makeStore()
        let spy = NativeIOSpy()
        store.magpieTransport = ClaudeMagpieFixture.transport(data: Data("""
        {"data":[{"provider":"claude","windows":[]},{"provider":"codex","windows":[]},
          {"provider":"kimi-code","windows":[]},{"provider":"opencode-go","windows":[]}]}
        """.utf8))
        if state == "firstFailure" {
            store.magpieTransport = ClaudeMagpieFixture.transport(status: 503)
        }
        if state == "laterFailure" || state == "disappeared" {
            store.reconcileMagpieSourceConfiguration()
            await store.awaitMagpieRefresh()
            store.magpieTransport = state == "laterFailure"
                ? ClaudeMagpieFixture.transport(status: 503)
                : ClaudeMagpieFixture.transport(data: Data(#"{"data":[]}"#.utf8))
            await store.refreshMagpieAccounts()
        }
        let intercept: @Sendable (NativeProviderIOTestBoundary.Kind) throws -> Void = { kind in
            spy.record(kind)
            throw CancellationError()
        }
        await NativeProviderIOTestBoundary.$intercept.withValue(intercept) {
            for provider: UsageProvider in [.claude, .codex, .kimi, .opencodego] {
                await store.refreshProvider(provider, allowDisabled: true)
                _ = await store.debugLog(for: provider)
                #expect(!store.providerSourceRoute(for: provider).isNative)
                for kind in NativeProviderIOTestBoundary.Kind.allCases {
                    #expect(spy.count(kind) == 0)
                }
            }
        }
    }

    @Test
    func `native IO spies intercept real APIs when unified source is off`() async {
        let store = self.makeStore()
        store.settings.magpieSourceEnabled = false
        let spy = NativeIOSpy()
        store._test_providerFetchOutcomeOverride = { provider in
            ProviderFetchOutcome(result: .failure(ProviderFetchError.noAvailableStrategy(provider)), attempts: [])
        }
        let intercept: @Sendable (NativeProviderIOTestBoundary.Kind) throws -> Void = { kind in
            spy.record(kind)
            throw CancellationError()
        }
        await NativeProviderIOTestBoundary.$intercept.withValue(intercept) {
            for provider: UsageProvider in [.claude, .codex, .kimi, .opencodego] {
                #expect(store.providerSourceRoute(for: provider).isNative)
                await store.refreshProvider(provider, allowDisabled: true)
                _ = store.makeFetchContext(provider: provider, override: nil)
            }
            _ = KimiSettingsReader.hasKimiCodeCredential(environment: ["HOME": "/fixture"])
            _ = try? ClaudeOAuthCredentialsStore.loadRecord(environment: [:], allowKeychainPrompt: false)
            _ = KeychainSecurity.copyMatching([kSecClass: kSecClassGenericPassword] as CFDictionary, nil)
            _ = try? OpenCodeCookieImporter.importSession(browserDetection: BrowserDetection(cacheTTL: 0))
            _ = try? KimiCookieImporter.importSessions(browserDetection: BrowserDetection(cacheTTL: 0))
            _ = try? await SubprocessRunner.run(
                binary: "/fixture/tool", arguments: [], environment: [:], timeout: 1, label: "fixture")
        }
        for kind in NativeProviderIOTestBoundary.Kind.allCases {
            #expect(spy.count(kind) > 0)
        }
    }

    @Test
    func `emptySuccessfulRefreshRetainsPreviousAccountsAsLastKnown`() async {
        let store = self.makeStore()
        await store.refreshMagpieAccounts()
        let before = store.magpieOverviewSnapshots
        store.magpieTransport = ClaudeMagpieFixture.transport(data: Data(#"{"data":[]}"#.utf8))
        await store.refreshMagpieAccounts()
        #expect(store.magpieOverviewSnapshots.count == before.count)
        #expect(Set(store.magpieOverviewSnapshots.map(\.id)) == Set(before.map(\.id)))
        let allRetained = store.magpieOverviewSnapshots.allSatisfy(\.usesLastKnownUsage)
        #expect(allRetained)
        #expect(store.magpieLastError != nil)
        for old in before {
            #expect(store.magpieOverviewSnapshots.first { $0.id == old.id }?.windows == old.windows)
        }
    }

    @Test
    func `firstEmptySuccessfulRefreshPublishesEmptyWithoutError`() async {
        let store = self.makeStore()
        store.magpieTransport = ClaudeMagpieFixture.transport(data: Data(#"{"data":[]}"#.utf8))
        await store.refreshMagpieAccounts()
        #expect(store.magpieOverviewSnapshots.isEmpty)
        #expect(store.magpieLastError == nil)
    }

    @Test
    func `empty provider windows retain previous quota data`() async {
        let store = self.makeStore()
        await store.refreshMagpieAccounts()
        let before = store.magpieAccountSnapshots.filter { $0.provider.wireID == "codex" }
        store.magpieTransport = ClaudeMagpieFixture.transport(
            data: Data(#"{"data":[{"provider":"codex","user":"codex@example.com","windows":[]}]}"#.utf8))
        await store.refreshMagpieAccounts()
        let after = store.magpieAccountSnapshots.filter { $0.provider.wireID == "codex" }
        #expect(after.count == before.count)
        #expect(after.first?.windows == before.first?.windows)
        let allRetained = after.allSatisfy(\.usesLastKnownUsage)
        #expect(allRetained)
    }

    @Test
    func `gateway failure and missing providers keep ownership`() async {
        let store = self.makeStore()
        await store.refreshMagpieAccounts()
        store.magpieTransport = ClaudeMagpieFixture.transport(status: 503)
        await store.refreshMagpieAccounts()
        #expect(!store.providerSourceRoute(for: .claude).isNative)
        #expect(!store.providerSourceRoute(for: .codex).isNative)
        #expect(store.magpieLastError != nil)
        store.magpieTransport = ClaudeMagpieFixture.transport(data: Data(#"{"data":[]}"#.utf8))
        await store.refreshMagpieAccounts()
        #expect(!store.providerSourceRoute(for: .codex).isNative)
    }

    @Test
    func `unmanaged providers remain native after a later gateway failure`() async {
        let store = self.makeStore()
        await store.refreshMagpieAccounts()
        #expect(store.providerSourceRoute(for: .kimi).isNative)
        #expect(store.providerSourceRoute(for: .opencodego).isNative)
        store.magpieTransport = ClaudeMagpieFixture.transport(status: 503)
        await store.refreshMagpieAccounts()
        #expect(store.providerSourceRoute(for: .kimi).isNative)
        #expect(store.providerSourceRoute(for: .opencodego).isNative)
        #expect(!store.providerSourceRoute(for: .claude).isNative)
        #expect(!store.providerSourceRoute(for: .codex).isNative)
    }

    @Test
    func `first discovery failure blocks native reads`() async {
        let store = self.makeStore()
        store.magpieTransport = ClaudeMagpieFixture.transport(status: 503)
        await store.refreshMagpieAccounts()
        for provider in [UsageProvider.claude, .codex, .kimi, .opencodego] {
            #expect(!store.providerSourceRoute(for: provider).isNative)
        }
    }

    @Test
    func `empty providers are hidden but remain owned`() async {
        let store = self.makeStore()
        store.magpieTransport = ClaudeMagpieFixture.transport(
            data: Data(
                #"{"data":[{"provider":"opencode-go","windows":[]},{"provider":"opencode-zen-free","windows":[]}]}"#
                    .utf8))
        await store.refreshMagpieAccounts()
        #expect(store.magpieOverviewSnapshots.isEmpty)
        #expect(!store.providerSourceRoute(for: .opencodego).isNative)
    }

    @Test(arguments: [UsageProvider.claude, .codex, .kimi, .opencodego])
    func `managed refresh debug and cost paths never enter native work`(provider: UsageProvider) async {
        let store = self.makeStore()
        store.magpieTransport = ClaudeMagpieFixture.transport(data: Data("""
        {"data":[{"provider":"claude","windows":[{"name":"5 hours","used":1}]},
          {"provider":"codex","windows":[{"name":"5 hours","used":1}]},
          {"provider":"kimi-code","windows":[{"name":"5 hours","used":1}]},
          {"provider":"opencode-go","windows":[{"name":"5 hours","used":1}]}]}
        """.utf8))
        var nativeRefreshes = 0
        var nativeCostReads = 0
        store._test_providerRefreshOverride = { _ in nativeRefreshes += 1 }
        store._test_tokenUsageRefreshOverride = { _, _ in nativeCostReads += 1 }
        store.reconcileMagpieSourceConfiguration()
        await store.awaitMagpieRefresh()
        await store.refreshProvider(provider)
        await store.refreshTokenUsage(provider, force: true)
        let note = await store.debugLog(for: provider)
        #expect(nativeRefreshes == 0)
        #expect(nativeCostReads == 0)
        if !store.providerSourceRoute(for: provider).isNative {
            #expect(note.contains("magpie"))
        }
    }

    @Test
    func `turning the switch off restores native routing`() async {
        let store = self.makeStore()
        await store.refreshMagpieAccounts()
        store.settings.magpieSourceEnabled = false
        #expect(store.providerSourceRoute(for: .claude).isNative)
        #expect(store.providerSourceRoute(for: .codex).isNative)
    }
}

private final class NativeIOSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [NativeProviderIOTestBoundary.Kind: Int] = [:]

    func record(_ kind: NativeProviderIOTestBoundary.Kind) {
        self.lock.withLock { self.counts[kind, default: 0] += 1 }
    }

    func count(_ kind: NativeProviderIOTestBoundary.Kind) -> Int {
        self.lock.withLock { self.counts[kind, default: 0] }
    }
}
