import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

extension StatusMenuTests {
    @Test
    func `overview rows expose provider detail submenus`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .openai
        settings.mergedMenuLastSelectedWasOverview = true
        settings.costUsageEnabled = true
        settings.costSummaryDisplayStyle = .both

        enableTestProviders([.openai, .codex], settings: settings)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let usage = OpenAIAPIUsageSnapshot(
            daily: [
                OpenAIAPIUsageSnapshot.DailyBucket(
                    day: "2023-11-14",
                    startTime: now,
                    endTime: now.addingTimeInterval(86400),
                    costUSD: 9,
                    requests: 12,
                    inputTokens: 100,
                    cachedInputTokens: 0,
                    outputTokens: 50,
                    totalTokens: 150,
                    lineItems: [],
                    models: []),
            ],
            updatedAt: now)
        store._setSnapshotForTesting(usage.toUsageSnapshot(), provider: .openai)

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        let openAIRow = try #require(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-openai"
        })
        let openAIDetail = try #require(openAIRow.submenu)
        openAIDetail.delegate?.menuNeedsUpdate?(openAIDetail)
        #expect((openAIDetail.items.first?.representedObject as? String)?.hasPrefix("overviewDetail-") == true)
        // The history chart sits inline below the detail, not behind another submenu.
        #expect(openAIDetail.items.contains {
            ($0.representedObject as? String) == StatusItemController.costHistoryChartID
        })
        #expect(!openAIDetail.items.contains { item in
            item.submenu?.items.contains {
                ($0.representedObject as? String) == StatusItemController.costHistoryChartID
            } == true
        })
    }

    @Test
    func `overview row shows no cost history chart for opencodego and no empty usage chart`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .opencodego
        settings.mergedMenuLastSelectedWasOverview = true
        settings.costUsageEnabled = true
        // Deliberately NOT `.costSubmenu`/`.both`: opencodego has real rate-limit bars (unlike
        // mistral), so its Overview row must fall through to Plan Usage here rather than
        // unconditionally preferring cost history the way mistral's Overview row does.
        settings.costSummaryDisplayStyle = .inlineSummary

        enableTestProviders([.opencodego, .codex], settings: settings)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let opencodegoSnapshot = OpenCodeGoUsageSnapshot(
            hasMonthlyUsage: true,
            rollingUsagePercent: 12,
            weeklyUsagePercent: 57,
            monthlyUsagePercent: 34,
            rollingResetInSec: 3600,
            weeklyResetInSec: 86400,
            monthlyResetInSec: 864_000,
            daily: [
                CostUsageDailyReport.Entry(
                    date: "2025-12-23",
                    inputTokens: nil,
                    outputTokens: nil,
                    totalTokens: nil,
                    requestCount: 5,
                    costUSD: 1.23,
                    modelsUsed: nil,
                    modelBreakdowns: nil),
            ],
            updatedAt: Date())
        store._setSnapshotForTesting(opencodegoSnapshot.toUsageSnapshot(), provider: .opencodego)

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        let opencodegoRow = try #require(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-opencodego"
        })
        let opencodegoDetail = try #require(opencodegoRow.submenu)
        opencodegoDetail.delegate?.menuNeedsUpdate?(opencodegoDetail)
        let chartIDs = opencodegoDetail.items.compactMap { $0.representedObject as? String }
        // Nothing was recorded, so no usage history chart either; cost history stays out as well.
        #expect(!chartIDs.contains(StatusItemController.usageHistoryChartID))
        #expect(!chartIDs.contains(StatusItemController.costHistoryChartID))
    }

    @Test
    func `overview row uses declarative details without bespoke submenu`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = true

        enableTestProviders([.zai, .claude], settings: settings)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let detailSection = try ProviderDetailSection(title: "Quota details", rows: [
            .init(label: "MCP quota", value: "50% used", secondaryValue: "100 limit · 50 remaining"),
            .init(label: "glm-4.5", value: "512"),
        ])
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 50,
                windowMinutes: nil,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: "MCP"),
            secondary: nil,
            details: [detailSection],
            updatedAt: now,
            identity: ProviderIdentitySnapshot(
                providerID: .zai,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: "Pro"))
        store._setSnapshotForTesting(snapshot, provider: .zai)

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        let zaiRow = try #require(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-zai"
        })
        // Without history data the detail stands alone: no chart and no empty placeholder.
        let zaiDetail = try #require(zaiRow.submenu)
        zaiDetail.delegate?.menuNeedsUpdate?(zaiDetail)
        let historyIDs = [
            StatusItemController.usageHistoryChartID,
            StatusItemController.costHistoryChartID,
            StatusItemController.storageBreakdownID,
        ]
        #expect(!zaiDetail.items.contains { historyIDs.contains($0.representedObject as? String ?? "") })
        #expect(!zaiDetail.items.contains { $0.identifier == StatusItemController.hostedSubviewUnavailableItemID })
        let details = try #require(store.snapshot(for: .zai)?.details.first)
        #expect(details.title == "Quota details")
        #expect(details.rows.contains { $0.label == "MCP quota" && $0.value == "50% used" })
        #expect(details.rows.contains { $0.label == "glm-4.5" && $0.value == "512" })

        #expect(settings.mergedMenuLastSelectedWasOverview)
        #expect(settings.selectedMenuProvider == .claude)
        #expect(menu.items.contains {
            ($0.representedObject as? String) == "overviewRow-zai"
        })
    }

    @Test
    func `magpie overview row offers refresh for that account`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = true

        // Overview only exists once more than one provider is enabled.
        enableTestProviders([.claude, .codex], settings: settings)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        // Enabling magpie clears snapshots and schedules a refresh. A transport that never completes keeps
        // that refresh from replacing the fixture with whatever the local magpie happens to serve.
        store.magpieTransport = { _ in
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        }
        settings.magpieSourceEnabled = true
        let accountID = ProviderAccountIdentity(source: "magpie", opaqueID: "claude:first@example.com")
        store.magpieAccountSnapshots = [
            MagpieAccountSnapshot(
                id: accountID,
                provider: MagpieProviderMapping.reference(for: "claude"),
                displayLabel: "main",
                accountEmail: "first@example.com",
                ordinal: 1,
                windows: [MagpieQuotaWindow(name: "5 hours", usedPercent: 12, resetsAt: nil)],
                readAt: Date(timeIntervalSince1970: 1_700_000_000),
                isActive: true,
                error: nil),
        ]

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        let row = try #require(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-claude#\(accountID.opaqueID)"
        })
        let refresh = try #require(row.submenu?.items.first {
            $0.action == #selector(StatusItemController.refreshClaudeAccount(_:))
        })
        #expect(refresh.title == L("Refresh Claude usage"))
        #expect(refresh.representedObject as? String == accountID.opaqueID)
        #expect(refresh.target as? StatusItemController === controller)

        // Provider-level Claude history and actions are not this account's, so the refresh item ends the submenu.
        let submenu = try #require(row.submenu)
        submenu.delegate?.menuNeedsUpdate?(submenu)
        #expect(submenu.items.last === refresh)
    }

    @Test
    func `magpie Overview includes disabled and unknown providers with every named window`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.mergedMenuLastSelectedWasOverview = true
        enableTestProviders([.claude, .codex, .grok], settings: settings)
        let fetcher = UsageFetcher(environment: [:])
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        store.magpieTransport = { _ in throw CancellationError() }
        settings.magpieSourceEnabled = true
        let accounts = MagpieAccountProjection.snapshots(from: [
            MagpieQuotaRow(
                provider: "opencode-go",
                email: "",
                organization: "",
                alias: nil,
                isLast: false,
                readAt: nil,
                windows: [
                    MagpieQuotaWindow(name: "5 hours", usedPercent: 12, resetsAt: nil),
                    MagpieQuotaWindow(name: "7 days", usedPercent: 63, resetsAt: nil),
                    MagpieQuotaWindow(name: "Month", usedPercent: 8, resetsAt: nil),
                ],
                error: nil),
            MagpieQuotaRow(
                provider: "future-provider",
                email: "",
                organization: "",
                alias: nil,
                isLast: false,
                readAt: nil,
                windows: [MagpieQuotaWindow(name: "Burst", usedPercent: 24, resetsAt: nil)]),
            MagpieQuotaRow(
                provider: "grok-plugin",
                email: "",
                organization: "",
                alias: nil,
                isLast: false,
                readAt: nil,
                windows: [MagpieQuotaWindow(name: "7 days", usedPercent: 42, resetsAt: nil)]),
        ])
        store.magpieAccountSnapshots = accounts
        settings.magpieTakeoverWireIDs = ["opencode-go", "future-provider", "grok-plugin"]
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }
        let rows = controller.overviewUsageRows(visibleProviders: [.opencodego, .grok])
        let row = try #require(rows.first)
        #expect(rows.count == 3)
        #expect(row.isMagpie)
        #expect(row.namedWindows?.map(\.label) == ["5h", "7d", "Mo"])
        #expect(row.namedWindows?.count == 3)
        #expect(row.errorText == nil)
        #expect(controller.overviewUsageRows(visibleProviders: []).count == 3)
        let unknown = try #require(rows.first { $0.providerName == "future-provider" })
        #expect(unknown.nativeProvider == nil)
        #expect(unknown.namedWindows?.map(\.label) == ["Burst"])
        // grok-plugin is taken over by the native Grok provider, so it appears exactly once
        // and never alongside a native Grok block.
        #expect(rows.filter { $0.providerName == "Grok" }.count == 1)
        let grok = try #require(rows.first { $0.providerName == "Grok" })
        #expect(grok.nativeProvider == .grok)
        #expect(grok.isMagpie)
        for detailRow in rows {
            let submenu = controller.makeOverviewDetailSubmenu(row: detailRow, width: 340)
            submenu.delegate?.menuNeedsUpdate?(submenu)
            #expect(submenu.items.count == 1)
        }
    }

    @Test
    func `a grok card keeps its provider slot when the takeover and the response use different wire ids`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.mergedMenuLastSelectedWasOverview = true
        enableTestProviders([.grok, .opencodego], settings: settings)
        let fetcher = UsageFetcher(environment: [:])
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        store.magpieTransport = { _ in throw CancellationError() }
        settings.magpieSourceEnabled = true
        store.magpieAccountSnapshots = MagpieAccountProjection.snapshots(from: [
            MagpieQuotaRow(
                provider: "grok-plugin",
                email: "g@example.com",
                organization: "",
                alias: nil,
                isLast: true,
                readAt: nil,
                windows: [MagpieQuotaWindow(name: "7 days", usedPercent: 42, resetsAt: nil)],
                error: nil),
            MagpieQuotaRow(
                provider: "opencode-go",
                email: "o@example.com",
                organization: "",
                alias: nil,
                isLast: true,
                readAt: nil,
                windows: [MagpieQuotaWindow(name: "5 hours", usedPercent: 12, resetsAt: nil)],
                error: nil),
        ])
        // The persisted takeover predates the rename: it owns "grok", the response says
        // "grok-plugin". The card still belongs in Grok's slot, not at the end of the list.
        settings.magpieTakeoverWireIDs = ["grok", "opencode-go"]
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }
        let rows = controller.overviewUsageRows(visibleProviders: [.grok, .opencodego])
        #expect(rows.map(\.providerName) == ["Grok", "OpenCode Go"])
        #expect(rows.filter { $0.nativeProvider == .grok }.count == 1)
    }

    @Test
    func `overview detail submenu ends with the provider's own actions`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.multiAccountMenuLayout = .segmented
        enableTestProviders([.claude, .codex], settings: settings)
        settings.addTokenAccount(provider: .claude, label: "Primary", token: "Bearer sk-ant-oat-primary")
        settings.addTokenAccount(provider: .claude, label: "Secondary", token: "Bearer sk-ant-oat-secondary")
        settings.setActiveTokenAccountIndex(0, for: .claude)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        let row = try #require(menu.items.first { ($0.representedObject as? String) == "overviewRow-claude" })
        let detail = try #require(row.submenu)
        detail.delegate?.menuNeedsUpdate?(detail)
        #expect((detail.items.first?.representedObject as? String)?.hasPrefix("overviewDetail-") == true)
        #expect(detail.items.contains { $0.view is TokenAccountSwitcherView })
        #expect(detail.items.last?.action == controller.selector(for: .statusPage).0)
        #expect(detail.items.contains { $0.action == controller.selector(for: .dashboard).0 })
        // App-wide rows stay in the main menu.
        #expect(!detail.items.contains { $0.view is MenuFooterBarView })
        #expect(!detail.items.contains { $0.action == controller.selector(for: .settings).0 })
    }

    @Test
    func `a refresh that completes while a detail submenu is open waits for it to close`() async throws {
        self.disableMenuCardsForTesting()
        let previousRefresh = StatusItemController.menuRefreshEnabled
        StatusItemController.setMenuRefreshEnabledForTesting(true)
        defer { StatusItemController.setMenuRefreshEnabledForTesting(previousRefresh) }
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        enableTestProviders([.claude, .codex], settings: settings)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.mergedMenu = menu
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }
        let row = try #require(menu.items.first { ($0.representedObject as? String) == "overviewRow-codex" })
        let detail = try #require(row.submenu)
        detail.delegate?.menuWillOpen?(detail)
        #expect(controller.openMenus[ObjectIdentifier(detail)] === detail)

        var rebuilds = 0
        controller._test_openMenuRebuildObserver = { rebuilt in
            if rebuilt === menu { rebuilds += 1 }
        }
        defer { controller._test_openMenuRebuildObserver = nil }
        // A completed data refresh invalidates the open menus.
        controller.invalidateMenus(refreshOpenMenus: true)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(rebuilds == 0)
        #expect(controller.menuNeedsRefresh(menu))
        #expect(row.submenu === detail)

        detail.delegate?.menuDidClose?(detail)
        #expect(controller.openMenus[ObjectIdentifier(detail)] == nil)
        for _ in 0..<50 where controller.menuNeedsRefresh(menu) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(!controller.menuNeedsRefresh(menu))
    }
}
