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
    func `overview chrome adds the header, the provider count and the footer status`() throws {
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
        #expect(ids.contains("overviewProviderCount"))
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
    func `overview retains every magpie window and provider`() throws {
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

        let rows = controller.overviewUsageRows(visibleProviders: [.claude, .codex])
        let claude = try #require(rows.first { $0.groupKey == "claude" })
        #expect(claude.namedWindows?.map(\.label) == ["5h", "7d"])
        #expect(rows.first { $0.groupKey == "futurewire" }?.namedWindows?.map(\.label) == ["7d"])
    }

    @Test
    func `overview retains both native windows`() throws {
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

        let row = try #require(
            controller.overviewUsageRows(visibleProviders: [.claude, .codex]).first { $0.groupKey == "codex" })
        #expect(row.snapshot?.primary?.usedPercent == 22)
        #expect(row.snapshot?.secondary?.usedPercent == 60)
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
}
