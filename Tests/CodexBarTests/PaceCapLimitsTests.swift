import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

/// pace-cap writes each account's daily allowance to a file beside magpie; the Overview marks it on the
/// account's bar.
@MainActor
struct PaceCapLimitsTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Keyed like magpie's rows. The first Claude account has an allowance on its weekly window; the codex
    /// entry names an account the fixture does not have; the last two are malformed and skipped.
    private static let limitsJSON = """
    {"accounts":[
      {"provider":"claude","user":"first@example.com · Example Org","window":"7 days","allowance":80},
      {"provider":"codex","user":"first@example.com · Example Org","window":"5 hours","allowance":5},
      {"provider":"claude","user":"second@example.com · Example Org","window":"7 days"},
      {"unexpected":true}
    ]}
    """

    private func store(limits: String?) throws -> UsageStore {
        let settings = testSettingsStore(
            suiteName: "PaceCapLimitsTests",
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
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pace-cap-limits-\(UUID().uuidString).json")
        if let limits {
            try Data(limits.utf8).write(to: url)
        }
        store.paceCapLimitsURL = url
        return store
    }

    /// Where each of the account's Overview lines draws the allowance mark, by window label.
    private func allowances(
        _ store: UsageStore,
        email: String,
        showsRemaining: Bool = false) throws -> [String: Double?]
    {
        let account = try #require(store.magpieOverviewSnapshots.first { $0.accountEmail == email })
        let row = OverviewUsageRow.magpie(account: account, providerName: "Claude", accountName: email)
        let view = OverviewCompactAccountRow(
            name: email,
            shortWindow: nil,
            longWindow: nil,
            width: 320,
            namedLines: row.compactLines(now: Self.now),
            display: OverviewDisplayOptions(showsRemaining: showsRemaining),
            now: Self.now)
        return Dictionary(uniqueKeysWithValues: view.lines.map { ($0.label, view.reading(for: $0).allowancePercent) })
    }

    @Test
    func `an account's allowance is marked on the window it names`() async throws {
        let store = try self.store(limits: Self.limitsJSON)
        await store.refreshMagpieAccounts()

        let used = try self.allowances(store, email: "first@example.com")
        #expect(used["7d"] == 80)
        #expect(used.filter { $0.key != "7d" }.values.allSatisfy { $0 == nil })
        #expect(try self.allowances(store, email: "first@example.com", showsRemaining: true)["7d"] == 20)
        #expect(try self.allowances(store, email: "second@example.com").values.allSatisfy { $0 == nil })
    }

    @Test(arguments: [nil, "not json", #"{"accounts":[]}"#])
    func `without a readable limits file no bar marks an allowance`(limits: String?) async throws {
        let store = try self.store(limits: limits)
        await store.refreshMagpieAccounts()

        let lines = try self.allowances(store, email: "first@example.com")
        #expect(!lines.isEmpty)
        #expect(lines.values.allSatisfy { $0 == nil })
    }
}
