import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

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

    @Test
    func `emptySuccessfulRefreshRetainsPreviousAccountsAsLastKnown`() async {
        let store = self.makeStore()
        await store.refreshMagpieAccounts()
        let before = store.magpieOverviewSnapshots
        store.magpieTransport = ClaudeMagpieFixture.transport(data: Data(#"{"data":[]}"#.utf8))
        await store.refreshMagpieAccounts()
        #expect(store.magpieOverviewSnapshots.count == before.count)
        #expect(Set(store.magpieOverviewSnapshots.map(\.id)) == Set(before.map(\.id)))
        #expect(store.magpieOverviewSnapshots.allSatisfy(\.usesLastKnownUsage))
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
        #expect(after.allSatisfy(\.usesLastKnownUsage))
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

    @Test
    func `turning the switch off restores native routing`() async {
        let store = self.makeStore()
        await store.refreshMagpieAccounts()
        store.settings.magpieSourceEnabled = false
        #expect(store.providerSourceRoute(for: .claude).isNative)
        #expect(store.providerSourceRoute(for: .codex).isNative)
    }
}
