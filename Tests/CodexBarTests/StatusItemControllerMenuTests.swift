import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct StatusItemControllerMenuTests {
    @MainActor
    private final class RecordingUpdater: UpdaterProviding {
        var automaticallyChecksForUpdates = false
        var automaticallyDownloadsUpdates = false
        let isAvailable = true
        let unavailableReason: String? = nil
        let updateStatus = UpdateStatus()
        var checkForUpdatesCount = 0
        var installUpdateCount = 0

        init() {
            self.updateStatus.isUpdateReady = true
        }

        func checkForUpdates(_ sender: Any?) {
            _ = sender
            self.checkForUpdatesCount += 1
        }

        func installUpdate() {
            self.installUpdateCount += 1
        }
    }

    private func makeSnapshot(
        primary: RateWindow?,
        secondary: RateWindow?,
        tertiary: RateWindow? = nil,
        extraRateWindows: [NamedRateWindow]? = nil,
        providerCost: ProviderCostSnapshot? = nil)
        -> UsageSnapshot
    {
        UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            extraRateWindows: extraRateWindows,
            providerCost: providerCost,
            updatedAt: Date())
    }

    @Test
    @MainActor
    func `menu card width stays at base width when menu accessories are present`() {
        let shortcutMenu = NSMenu()
        let refreshItem = NSMenuItem(title: "Refresh", action: nil, keyEquivalent: "r")
        shortcutMenu.addItem(refreshItem)
        #expect(ceil(shortcutMenu.size.width) < 310)

        let submenuMenu = NSMenu()
        let parentItem = NSMenuItem(title: "Session", action: nil, keyEquivalent: "")
        parentItem.submenu = NSMenu(title: "Session")
        submenuMenu.addItem(parentItem)
        #expect(ceil(submenuMenu.size.width) < 310)
    }

    // MARK: - Status component allowlist

    @Test
    @MainActor
    func `status component allowlist passes through unfiltered for providers without one`() {
        let components = [
            ProviderStatusComponent(id: "1", name: "API", indicator: .none, status: "operational"),
            ProviderStatusComponent(id: "2", name: "Web App", indicator: .none, status: "operational"),
        ]

        let filtered = StatusItemController.filterStatusComponents(components, for: .claude)

        #expect(filtered.map(\.name) == ["API", "Web App"])
    }

    @Test
    @MainActor
    func `status component allowlist keeps only named components and groups for zoommate`() {
        let components = [
            ProviderStatusComponent(
                id: "g1",
                name: "Zoom Meetings",
                indicator: .none,
                status: "operational",
                children: [
                    ProviderStatusComponent(
                        id: "c1",
                        name: "Zoom Whiteboard",
                        indicator: .none,
                        status: "operational"),
                ]),
            ProviderStatusComponent(id: "2", name: "ZoomMate", indicator: .none, status: "operational"),
            ProviderStatusComponent(id: "3", name: "My Notes", indicator: .none, status: "operational"),
            ProviderStatusComponent(
                id: "g2",
                name: "Zoom Workflows",
                indicator: .none,
                status: "operational",
                children: [
                    ProviderStatusComponent(
                        id: "c2",
                        name: "Zoom AIC",
                        indicator: .none,
                        status: "operational"),
                ]),
            ProviderStatusComponent(id: "4", name: "Zoom Phone - US", indicator: .none, status: "operational"),
            ProviderStatusComponent(id: "5", name: "Zoom Rooms", indicator: .none, status: "operational"),
        ]

        let filtered = StatusItemController.filterStatusComponents(components, for: .zoommate)

        #expect(filtered.map(\.name) == ["Zoom Meetings", "ZoomMate", "My Notes", "Zoom Workflows"])
        // Allowlisted groups keep their existing full child list; the allowlist filters at the
        // top level only, it does not additionally prune group children.
        #expect(filtered.first { $0.name == "Zoom Meetings" }?.children.map(\.name) == ["Zoom Whiteboard"])
    }

    @Test
    @MainActor
    func `status component allowlist tolerates any subset of named components being absent`() {
        // Only two of the four allowlisted names are present; the other two are silently omitted
        // without error, and unrelated components remain excluded as usual.
        let components = [
            ProviderStatusComponent(id: "2", name: "ZoomMate", indicator: .none, status: "operational"),
            ProviderStatusComponent(id: "4", name: "Zoom Phone - US", indicator: .none, status: "operational"),
            ProviderStatusComponent(id: "3", name: "My Notes", indicator: .minor, status: "degraded_performance"),
        ]

        let filtered = StatusItemController.filterStatusComponents(components, for: .zoommate)

        #expect(filtered.map(\.name) == ["ZoomMate", "My Notes"])
    }

    @Test
    @MainActor
    func `status component allowlist returns empty list when all named components are absent`() {
        // Zoom's status page has been fully restructured and none of the four allowlisted names
        // remain; the filter must degrade to an empty list rather than crash, so the existing
        // "no components" gate (which shows only the website link) takes over.
        let components = [
            ProviderStatusComponent(id: "4", name: "Zoom Phone - US", indicator: .none, status: "operational"),
            ProviderStatusComponent(id: "5", name: "Zoom Rooms", indicator: .none, status: "operational"),
        ]

        let filtered = StatusItemController.filterStatusComponents(components, for: .zoommate)

        #expect(filtered.isEmpty)
    }

    @Test
    @MainActor
    func `status component allowlist on an empty component list stays empty`() {
        let filtered = StatusItemController.filterStatusComponents([], for: .zoommate)
        #expect(filtered.isEmpty)
    }

    @Test
    @MainActor
    func `update menu action installs prepared update instead of checking again`() throws {
        let suite = "StatusItemControllerMenuTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        let settings = SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let updater = RecordingUpdater()
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: updater,
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)

        controller.installUpdate()

        #expect(updater.installUpdateCount == 1)
        #expect(updater.checkForUpdatesCount == 0)
    }
}
