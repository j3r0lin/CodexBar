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
        #expect((openAIDetail.items.first?.representedObject as? String)?.hasPrefix("overviewDetail-") == true)
        #expect(openAIDetail.items.contains {
            $0.submenu?.items.contains {
                ($0.representedObject as? String) == StatusItemController.costHistoryChartID
            } == true
        })
    }

    @Test
    func `overview row shows plan usage not cost history for opencodego`() throws {
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
        let chartIDs = opencodegoRow.submenu?.items.flatMap {
            $0.submenu?.items.compactMap { $0.representedObject as? String } ?? []
        } ?? []
        #expect(chartIDs.contains(StatusItemController.usageHistoryChartID))
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
        // Only the shared usage detail; no bespoke chart submenu.
        #expect(zaiRow.submenu?.items.count == 1)
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
}
