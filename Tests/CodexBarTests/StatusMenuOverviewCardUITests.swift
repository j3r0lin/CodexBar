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
    func `overview chrome adds the header, the provider count and the footer status`() {
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
        #expect(!ids.contains("overviewProviderCount"))
        #expect(ids.contains("overviewFooterStatus"))
        #expect(ids.first == "overviewHeader")
        #expect(ids.last == "overviewFooterStatus")

        // About and Quit live in the footer row, so the Overview menu has no icon bar.
        #expect(!menu.items.contains { $0.view is MenuFooterBarView })
        // No edge-to-edge native separator above the footer; the last card's border closes the content.
        #expect(menu.items.dropLast().last?.isSeparatorItem == false)
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
    func `hidden usage items take their windows off a native overview row`() throws {
        self.disableMenuCardsForTesting()
        let (settings, store) = self.makeOverviewFixture()
        enableTestProviders([.claude, .codex], settings: settings)
        let session = RateWindow(
            usedPercent: 40,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(1800),
            resetDescription: nil)
        let weekly = RateWindow(
            usedPercent: 70,
            windowMinutes: 7 * 1440,
            resetsAt: Date().addingTimeInterval(172_800),
            resetDescription: nil)
        store._setSnapshotForTesting(
            UsageSnapshot(primary: session, secondary: weekly, updatedAt: Date()),
            provider: .codex)
        let controller = self.makeOverviewController(settings: settings, store: store)
        defer { controller.releaseStatusItemsForTesting() }

        func lines() throws -> [OverviewCompactAccountRow.Line] {
            let row = try #require(
                controller.overviewUsageRows(visibleProviders: [.claude, .codex]).first { $0.groupKey == "codex" })
            return controller.overviewRowView(for: row, width: 320, isGrouped: false, now: Date()).lines
        }
        #expect(try lines().map(\.used) == [40, 70])

        settings.setUsageItemVisible(false, itemID: .metric("primary"), for: .codex)
        #expect(try lines().map(\.used) == [70])

        settings.setUsageItemVisible(false, itemID: .metric("secondary"), for: .codex)
        #expect(try lines().isEmpty)

        settings.restoreDefaultUsageItemVisibility(for: .codex)
        #expect(try lines().count == 2)
    }

    @Test
    func `overview rows follow the used or remaining choice and the pace switch`() throws {
        self.disableMenuCardsForTesting()
        let (settings, store) = self.makeOverviewFixture()
        enableTestProviders([.claude, .codex], settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 40,
                    windowMinutes: 300,
                    resetsAt: Date().addingTimeInterval(7200),
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 70,
                    windowMinutes: 7 * 1440,
                    resetsAt: Date().addingTimeInterval(4 * 86400),
                    resetDescription: nil),
                updatedAt: Date()),
            provider: .codex)
        settings.usageBarsShowUsed = true
        let controller = self.makeOverviewController(settings: settings, store: store)
        defer { controller.releaseStatusItemsForTesting() }
        let row = try #require(
            controller.overviewUsageRows(visibleProviders: [.claude, .codex]).first { $0.groupKey == "codex" })

        let used = controller.overviewRowView(for: row, width: 320, isGrouped: false, now: Date())
        #expect(used.display.showsRemaining == false)
        #expect(used.display.showsPace)
        #expect(used.lines.map { used.reading(for: $0).percent } == [40, 70])

        settings.usageBarsShowUsed = false
        let remaining = controller.overviewRowView(for: row, width: 320, isGrouped: false, now: Date())
        #expect(remaining.display.showsRemaining)
        #expect(remaining.lines.map(\.used) == used.lines.map(\.used))
        #expect(remaining.lines.map { remaining.reading(for: $0).percent } == [60, 30])

        settings.paceVisible = false
        let unpace = controller.overviewRowView(for: row, width: 320, isGrouped: false, now: Date())
        #expect(!unpace.display.showsPace)
    }

    @Test
    func `overview rows use the provider warning thresholds`() throws {
        self.disableMenuCardsForTesting()
        let (settings, store) = self.makeOverviewFixture()
        enableTestProviders([.claude, .codex], settings: settings)
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 60,
                    windowMinutes: 300,
                    resetsAt: nil,
                    resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .codex)
        let controller = self.makeOverviewController(settings: settings, store: store)
        defer { controller.releaseStatusItemsForTesting() }
        let row = try #require(
            controller.overviewUsageRows(visibleProviders: [.claude, .codex]).first { $0.groupKey == "codex" })

        settings.quotaWarningThresholds = [40, 10]
        let view = controller.overviewRowView(for: row, width: 320, isGrouped: false, now: Date())
        #expect(view.display.sessionWarningThresholds == [40, 10])
        #expect(view.display.weeklyWarningThresholds == [40, 10])
        let line = try #require(view.lines.first)
        #expect(view.reading(for: line).barColor == OverviewPalette.warning)
    }

    @Test
    func `every magpie account keeps its own row without group headings`() {
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

        let ids = rowIDs()
        #expect(ids.filter { $0.hasPrefix("overviewRow-claude#") }.count == 2)
        #expect(!ids.contains { $0.hasPrefix("overviewHeading-") })
    }

    @Test
    func `a scheduled reset badge shows on Codex rows only`() throws {
        self.disableMenuCardsForTesting()
        let (settings, store) = self.makeOverviewFixture()
        enableTestProviders([.claude, .codex], settings: settings)
        let window = RateWindow(
            usedPercent: 40,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(1800),
            resetDescription: nil)
        for provider in [UsageProvider.claude, .codex] {
            store._setSnapshotForTesting(
                UsageSnapshot(primary: window, secondary: nil, updatedAt: Date()),
                provider: provider)
        }
        store.codexScheduledReset = CodexScheduledReset(
            scheduledFor: Date().addingTimeInterval(3600),
            sourceURL: nil)
        let controller = self.makeOverviewController(settings: settings, store: store)
        defer { controller.releaseStatusItemsForTesting() }

        func badge(_ groupKey: String) throws -> String? {
            let row = try #require(
                controller.overviewUsageRows(visibleProviders: [.claude, .codex]).first { $0.groupKey == groupKey })
            return controller.overviewRowView(for: row, width: 320, isGrouped: false, now: Date()).scheduledResetText
        }
        #expect(try badge("codex") != nil)
        #expect(try badge("claude") == nil)

        settings.magpieSourceEnabled = true
        settings.magpieTakeoverWireIDs = ["codex", "claude"]
        store.magpieAccountSnapshots = ["codex", "claude"].map { wireID in
            MagpieAccountSnapshot(
                id: ProviderAccountIdentity(source: "magpie", opaqueID: "\(wireID):account"),
                provider: MagpieProviderMapping.reference(for: wireID),
                displayLabel: "Account",
                accountEmail: nil,
                ordinal: 1,
                windows: [MagpieQuotaWindow(name: "5 hours", usedPercent: 12, resetsAt: nil)],
                readAt: Date(),
                isActive: true,
                error: nil)
        }
        #expect(try badge("codex") != nil)
        #expect(try badge("claude") == nil)

        store.codexScheduledReset = CodexScheduledReset(
            scheduledFor: Date().addingTimeInterval(3600),
            sourceURL: URL(string: "https://x.com/example/status/2"))
        let codexRow = try #require(
            controller.overviewUsageRows(visibleProviders: [.claude, .codex]).first { $0.groupKey == "codex" })
        let submenu = controller.makeOverviewDetailSubmenu(row: codexRow, width: 320)
        submenu.delegate?.menuNeedsUpdate?(submenu)
        #expect(submenu.items.last?.representedObject as? URL == store.codexScheduledReset?.sourceURL)
        #expect(submenu.items.last?.action != nil)

        settings.codexScheduledResetVisible = false
        #expect(try badge("codex") == nil)
    }
}
