import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
private final class SwitcherRefreshManualGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if self.isOpen {
            self.isOpen = false
            return
        }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        if let continuation = self.continuation {
            continuation.resume()
            self.continuation = nil
        } else {
            self.isOpen = true
        }
    }
}

@MainActor
@Suite(.serialized)
struct StatusMenuSwitcherRefreshTests {
    @Test
    func `smart provider switch resizes persistent refresh row to rendered menu width`() throws {
        let previousMenuCardRendering = StatusItemController.menuCardRenderingEnabled
        let previousMenuRefresh = StatusItemController.menuRefreshEnabled
        StatusItemController.menuCardRenderingEnabled = true
        StatusItemController.setMenuRefreshEnabledForTesting(false)
        defer {
            StatusItemController.menuCardRenderingEnabled = previousMenuCardRendering
            StatusItemController.setMenuRefreshEnabledForTesting(previousMenuRefresh)
        }

        let settings = Self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        Self.enableCodexAndClaude(settings)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        menu.minimumWidth = 420

        let descriptor = controller.makeMenuDescriptor(provider: .claude, includeContextualActions: true)
        controller.updateMenuContentPreservingSwitcher(
            menu,
            context: StatusItemController.MenuUpdateContext(
                provider: .claude,
                currentProvider: .claude,
                switcherSelection: .provider(.claude),
                menuWidth: StatusItemController.menuCardBaseWidth,
                codexAccountDisplay: nil,
                tokenAccountDisplay: nil,
                openAIContext: StatusItemController.OpenAIWebContext(
                    hasUsageBreakdown: false,
                    hasCreditsHistory: false,
                    hasCostHistory: false,
                    canShowBuyCredits: false,
                    hasOpenAIWebMenuItems: false),
                descriptor: descriptor))

        let expectedWidth = controller.renderedMenuWidth(for: menu)
        #expect(expectedWidth == 420)
        let refreshView = try #require(menu.items.first { $0.title == "Refresh" }?.view as? PersistentRefreshMenuView)
        #expect(abs(refreshView.frame.width - expectedWidth) <= 0.5)
    }

    @Test
    func `full cached reattachment resynchronizes detached refresh item`() throws {
        let previousMenuCardRendering = StatusItemController.menuCardRenderingEnabled
        StatusItemController.menuCardRenderingEnabled = false
        defer { StatusItemController.menuCardRenderingEnabled = previousMenuCardRendering }

        let settings = Self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        Self.enableCodexAndClaude(settings)
        Self.disableOverview(settings)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer {
            controller.manualRefreshTasks.values.forEach { $0.cancel() }
            controller.releaseStatusItemsForTesting()
        }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let cache = try #require(
            controller.mergedSwitcherContentCaches[ObjectIdentifier(menu)]?[.provider(.codex)])
        let refreshItem = try #require(cache.items.first { $0.title == "Refresh" })

        controller.manualRefreshTasks[.global] = Task {}
        controller.updatePersistentRefreshItemsEnabled()
        #expect(!refreshItem.isEnabled)

        menu.removeAllItems()
        #expect(refreshItem.menu == nil)
        controller.manualRefreshTasks[.global] = nil
        controller.updatePersistentRefreshItemsEnabled()
        #expect(!refreshItem.isEnabled)

        #expect(controller.addCachedMergedSwitcherContent(
            for: .provider(.codex),
            to: menu,
            menuWidth: cache.menuWidth,
            codexAccountDisplay: cache.codexAccountDisplay,
            tokenAccountDisplay: cache.tokenAccountDisplay))
        #expect(refreshItem.menu === menu)
        #expect(refreshItem.isEnabled)
    }

    @Test
    func `a provider manual refresh only greys its own tab`() {
        let settings = Self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .codex
        Self.enableCodexAndClaude(settings)
        Self.disableOverview(settings)

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer {
            controller.manualRefreshTasks.values.forEach { $0.cancel() }
            controller.manualRefreshTasks.removeAll()
            controller.releaseStatusItemsForTesting()
        }

        let menu = controller.makeMenu()
        controller.mergedMenu = menu
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        // A manual refresh of Claude must leave the Codex tab's Refresh row enabled.
        controller.manualRefreshTasks[.provider(.claude)] = Task {}
        #expect(!controller.isRefreshActionInFlight(for: menu))

        // Switching to the Claude tab reflects Claude's own in-flight refresh.
        settings.selectedMenuProvider = .claude
        #expect(controller.isRefreshActionInFlight(for: menu))

        // An all-providers refresh busies every tab regardless of the selected provider.
        settings.selectedMenuProvider = .codex
        controller.manualRefreshTasks[.provider(.claude)] = nil
        controller.manualRefreshTasks[.global] = Task {}
        #expect(controller.isRefreshActionInFlight(for: menu))
    }

    @Test
    func `native image menu rows are replaced during reconciliation`() {
        let settings = Self.makeSettings()
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer { controller.releaseStatusItemsForTesting() }

        let menu = NSMenu()
        let liveItem = Self.nativeImageItem(title: "Status Page")
        menu.addItem(liveItem)
        let shapes = controller.menuContentShapes(in: menu, fromIndex: 0)

        let scratch = NSMenu()
        let freshItem = Self.nativeImageItem(title: "Status Page")
        scratch.addItem(freshItem)

        controller.reconcileMenuContent(menu, fromIndex: 0, shapes: shapes, with: scratch)

        #expect(menu.items.count == 1)
        #expect(ObjectIdentifier(menu.items[0]) == ObjectIdentifier(freshItem))
        #expect(ObjectIdentifier(menu.items[0]) != ObjectIdentifier(liveItem))
    }

    @Test
    func `native image submenu rows reconcile in place`() {
        let settings = Self.makeSettings()
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
        defer { controller.releaseStatusItemsForTesting() }

        let menu = NSMenu()
        let liveItem = Self.nativeImageItem(title: "System Account")
        liveItem.submenu = NSMenu(title: "System Account")
        menu.addItem(liveItem)
        let shapes = controller.menuContentShapes(in: menu, fromIndex: 0)

        let scratch = NSMenu()
        let freshItem = Self.nativeImageItem(title: "System Account")
        freshItem.submenu = NSMenu(title: "System Account")
        scratch.addItem(freshItem)

        controller.reconcileMenuContent(menu, fromIndex: 0, shapes: shapes, with: scratch)

        #expect(menu.items.count == 1)
        #expect(ObjectIdentifier(menu.items[0]) == ObjectIdentifier(liveItem))
        #expect(ObjectIdentifier(menu.items[0]) != ObjectIdentifier(freshItem))
    }

    private static func makeSettings() -> SettingsStore {
        let suite = "StatusMenuSwitcherRefreshTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: "providerDetectionCompleted")
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private static func enableCodexAndClaude(_ settings: SettingsStore) {
        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            let shouldEnable = provider == .codex || provider == .claude
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: shouldEnable)
        }
    }

    private static func disableOverview(_ settings: SettingsStore) {
        let activeProviders: [UsageProvider] = [.codex, .claude]
        _ = settings.setMergedOverviewProviderSelection(
            provider: .codex,
            isSelected: false,
            activeProviders: activeProviders)
        _ = settings.setMergedOverviewProviderSelection(
            provider: .claude,
            isSelected: false,
            activeProviders: activeProviders)
    }

    private static func quotaSnapshot(usedPercent: Double, updatedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            primary: RateWindow(
                usedPercent: usedPercent,
                windowMinutes: 300,
                resetsAt: updatedAt.addingTimeInterval(3600),
                resetDescription: nil),
            secondary: nil,
            updatedAt: updatedAt)
    }

    private static func waitForRebuildCount(
        _ expectedCount: Int,
        rebuildCount: () -> Int) async
    {
        for _ in 0..<100 where rebuildCount() < expectedCount {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private static func nativeImageItem(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(size: NSSize(width: 16, height: 16))
        return item
    }
}
