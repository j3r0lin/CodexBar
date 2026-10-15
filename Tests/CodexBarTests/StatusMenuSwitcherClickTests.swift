import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct StatusMenuSwitcherClickTests {
    private func makeStatusBarForTesting() -> NSStatusBar {
        // Use the real system status bar in tests. Creating standalone NSStatusBar instances
        // has caused AppKit teardown crashes under swiftpm-testing-helper.
        .system
    }

    private func makeSettings() -> SettingsStore {
        let suite = "StatusMenuSwitcherClickTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let configStore = testConfigStore(suiteName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: configStore,
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func makeInstalledSwitcherShortcutMonitor() -> (controller: StatusItemController, menu: StatusItemMenu) {
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true

        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            let shouldEnable = provider == .codex || provider == .claude
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: shouldEnable)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())

        let menu = StatusItemMenu()
        let refreshItem = NSMenuItem()
        refreshItem.representedObject = StatusItemController.persistentRefreshMenuItemID
        menu.addItem(refreshItem)

        controller.installProviderSwitcherShortcutMonitorIfNeeded(for: menu)
        return (controller, menu)
    }

    @Test
    func `provider shortcut monitor is removed when tracked menu closes after switcher rebuild`() {
        let previousMenuRefresh = StatusItemController.menuRefreshEnabled
        StatusItemController.setMenuRefreshEnabledForTesting(true)
        defer {
            StatusItemController.setMenuRefreshEnabledForTesting(previousMenuRefresh)
        }

        let (controller, menu) = self.makeInstalledSwitcherShortcutMonitor()
        defer { controller.releaseStatusItemsForTesting() }

        #expect(controller.providerSwitcherShortcutEventMonitor != nil)
        #expect(controller.providerSwitcherShortcutMenuID == ObjectIdentifier(menu))

        menu.removeAllItems()
        controller.menuDidClose(menu)

        #expect(controller.providerSwitcherShortcutEventMonitor == nil)
        #expect(controller.providerSwitcherShortcutMenuID == nil)
    }

    @Test
    func `switcher shortcut monitor is removed from direct close cleanup`() {
        let previousMenuRefresh = StatusItemController.menuRefreshEnabled
        StatusItemController.setMenuRefreshEnabledForTesting(true)
        defer {
            StatusItemController.setMenuRefreshEnabledForTesting(previousMenuRefresh)
        }

        let (controller, menu) = self.makeInstalledSwitcherShortcutMonitor()
        defer { controller.releaseStatusItemsForTesting() }

        #expect(controller.providerSwitcherShortcutEventMonitor != nil)
        #expect(controller.providerSwitcherShortcutMenuID == ObjectIdentifier(menu))

        controller.forgetClosedMenu(menu)

        #expect(controller.providerSwitcherShortcutEventMonitor == nil)
        #expect(controller.providerSwitcherShortcutMenuID == nil)
    }
}
