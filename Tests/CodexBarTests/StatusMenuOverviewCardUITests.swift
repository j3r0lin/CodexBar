import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
extension StatusMenuTests {
    private func makeOverviewController(
        settings: SettingsStore,
        store: UsageStore) -> StatusItemController
    {
        StatusItemController(
            store: store,
            settings: settings,
            account: AccountInfo(email: nil, plan: nil),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
    }

    private func makeOverviewFixture() -> (SettingsStore, UsageStore) {
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.mergedMenuLastSelectedWasOverview = true
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        return (settings, store)
    }

    @Test
    func `overview chrome adds the header, the filter bar and the footer status`() throws {
        self.disableMenuCardsForTesting()
        let (settings, store) = self.makeOverviewFixture()
        enableTestProviders([.claude, .codex], settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 22,
                    windowMinutes: 300,
                    resetsAt: Date().addingTimeInterval(1800),
                    resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .codex)
        let controller = self.makeOverviewController(settings: settings, store: store)
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        let ids = menu.items.compactMap { $0.representedObject as? String }
        #expect(ids.contains("overviewHeader"))
        #expect(ids.contains("overviewFilterBar"))
        #expect(ids.contains("overviewFooterStatus"))
        #expect(ids.first == "overviewHeader")
        #expect(ids.last == "overviewFooterStatus")

        // Refresh and Settings moved to the header; the footer bar keeps About and Quit.
        let bar = try #require(menu.items.first {
            $0.representedObject as? String == StatusItemController.menuFooterBarItemID
        })
        let barView = try #require(bar.view as? MenuFooterBarView)
        #expect(barView.button(labeled: L("Refresh")) == nil)
        #expect(barView.button(labeled: L("Settings...")) == nil)
        #expect(barView.button(labeled: L("Quit")) != nil)
    }

    @Test
    func `window filter hides non-matching windows and drops empty rows`() throws {
        self.disableMenuCardsForTesting()
        let (settings, store) = self.makeOverviewFixture()
        enableTestProviders([.claude, .codex], settings: settings)
        store.magpieTransport = { _ in throw CancellationError() }
        settings.magpieSourceEnabled = true
        settings.magpieTakeoverWireIDs = ["claude", "futurewire"]
        store.magpieAccountSnapshots = [
            MagpieAccountSnapshot(
                id: ProviderAccountIdentity(source: "magpie", opaqueID: "claude:main"),
                provider: MagpieProviderMapping.reference(for: "claude"),
                displayLabel: "main",
                accountEmail: nil,
                ordinal: 1,
                windows: [
                    MagpieQuotaWindow(name: "5 hours", usedPercent: 12, resetsAt: nil),
                    MagpieQuotaWindow(name: "7 days", usedPercent: 63, resetsAt: nil),
                ],
                readAt: Date(),
                isActive: true,
                error: nil),
            MagpieAccountSnapshot(
                id: ProviderAccountIdentity(source: "magpie", opaqueID: "futurewire:main"),
                provider: MagpieProviderMapping.reference(for: "futurewire"),
                displayLabel: "main",
                accountEmail: nil,
                ordinal: 1,
                windows: [MagpieQuotaWindow(name: "7 days", usedPercent: 40, resetsAt: nil)],
                readAt: Date(),
                isActive: true,
                error: nil),
        ]
        let controller = self.makeOverviewController(settings: settings, store: store)
        defer { controller.releaseStatusItemsForTesting() }

        let unfiltered = controller.overviewUsageRows(visibleProviders: [.claude, .codex])
        let claude = try #require(unfiltered.first { $0.groupKey == "claude" })
        #expect(claude.namedWindows?.count == 2)
        #expect(unfiltered.contains { $0.groupKey == "futurewire" })

        settings.overviewWindowFilter = .fiveHours
        let sessionOnly = controller.overviewUsageRows(visibleProviders: [.claude, .codex])
        #expect(sessionOnly.first { $0.groupKey == "claude" }?.namedWindows?.map(\.label) == ["5h"])
        #expect(!sessionOnly.contains { $0.groupKey == "futurewire" })

        settings.overviewWindowFilter = .sevenDays
        let weeklyOnly = controller.overviewUsageRows(visibleProviders: [.claude, .codex])
        #expect(weeklyOnly.first { $0.groupKey == "claude" }?.namedWindows?.map(\.label) == ["7d"])
        #expect(weeklyOnly.contains { $0.groupKey == "futurewire" })
    }

    @Test
    func `window filter keeps only the matching native slot`() throws {
        self.disableMenuCardsForTesting()
        let (settings, store) = self.makeOverviewFixture()
        enableTestProviders([.claude, .codex], settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 22,
                    windowMinutes: 300,
                    resetsAt: Date().addingTimeInterval(1800),
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 60,
                    windowMinutes: 10080,
                    resetsAt: Date().addingTimeInterval(172_800),
                    resetDescription: nil),
                updatedAt: Date()),
            provider: .codex)
        let controller = self.makeOverviewController(settings: settings, store: store)
        defer { controller.releaseStatusItemsForTesting() }

        settings.overviewWindowFilter = .fiveHours
        let sessionOnly = try #require(
            controller.overviewUsageRows(visibleProviders: [.claude, .codex]).first { $0.groupKey == "codex" })
        #expect(sessionOnly.slotOverride?.short != nil)
        #expect(sessionOnly.slotOverride?.long == nil)

        settings.overviewWindowFilter = .sevenDays
        let weeklyOnly = try #require(
            controller.overviewUsageRows(visibleProviders: [.claude, .codex]).first { $0.groupKey == "codex" })
        #expect(weeklyOnly.slotOverride?.short == nil)
        #expect(weeklyOnly.slotOverride?.long != nil)
    }

    @Test
    func `a collapsed provider group keeps only its header and the state persists`() {
        self.disableMenuCardsForTesting()
        let (settings, store) = self.makeOverviewFixture()
        enableTestProviders([.claude, .codex], settings: settings)
        store.magpieTransport = { _ in throw CancellationError() }
        settings.magpieSourceEnabled = true
        settings.magpieTakeoverWireIDs = ["claude"]
        store.magpieAccountSnapshots = (1...2).map { ordinal in
            MagpieAccountSnapshot(
                id: ProviderAccountIdentity(source: "magpie", opaqueID: "claude:acct\(ordinal)"),
                provider: MagpieProviderMapping.reference(for: "claude"),
                displayLabel: "acct\(ordinal)",
                accountEmail: nil,
                ordinal: ordinal,
                windows: [MagpieQuotaWindow(name: "5 hours", usedPercent: 12, resetsAt: nil)],
                readAt: Date(),
                isActive: ordinal == 1,
                error: nil)
        }
        let controller = self.makeOverviewController(settings: settings, store: store)
        defer { controller.releaseStatusItemsForTesting() }

        func rowIDs() -> [String] {
            let menu = controller.makeMenu()
            controller.menuWillOpen(menu)
            defer { controller.menuDidClose(menu) }
            return menu.items.compactMap { $0.representedObject as? String }
        }

        let expanded = rowIDs()
        #expect(expanded.contains { $0.hasPrefix("overviewRow-claude#") })
        #expect(expanded.contains("overviewHeading-claude"))

        settings.overviewCollapsedProviderGroups = ["claude"]
        let collapsed = rowIDs()
        #expect(!collapsed.contains { $0.hasPrefix("overviewRow-claude#") })
        #expect(collapsed.contains("overviewHeading-claude"))

        // The choice survives a settings reload from the same defaults.
        let reloaded = SettingsStore(
            userDefaults: settings.userDefaults,
            configStore: settings.configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(reloaded.overviewCollapsedProviderGroups == ["claude"])
    }

    @Test
    func `window filter persists and unknown values fall back to now`() {
        let settings = self.makeSettings()
        #expect(settings.overviewWindowFilter == .now)
        settings.overviewWindowFilter = .sevenDays
        let reloaded = SettingsStore(
            userDefaults: settings.userDefaults,
            configStore: settings.configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(reloaded.overviewWindowFilter == .sevenDays)
        settings.userDefaults.set("bogus", forKey: "overviewWindowFilter")
        let reloadedBogus = SettingsStore(
            userDefaults: settings.userDefaults,
            configStore: settings.configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        #expect(reloadedBogus.overviewWindowFilter == .now)
    }
}
