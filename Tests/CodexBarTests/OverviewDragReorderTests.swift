import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

extension StatusMenuTests {
    /// The drop has to rebuild the still-tracking menu on the event-tracking run loop. A main-actor
    /// task starves while AppKit owns the modal menu loop, which would leave the dividers stale
    /// until the menu is opened again.
    @Test
    func `a dropped overview row rebuilds the open menu during tracking`() throws {
        let previousRendering = StatusItemController.menuCardRenderingEnabled
        StatusItemController.menuCardRenderingEnabled = true
        StatusItemController.setMenuRefreshEnabledForTesting(true)
        defer {
            StatusItemController.menuCardRenderingEnabled = previousRendering
            StatusItemController.setMenuRefreshEnabledForTesting(false)
        }

        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.mergedMenuLastSelectedWasOverview = true
        enableTestProviders([.codex, .claude], settings: settings)

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

        func rowIdentifiers() -> [String] {
            menu.items
                .compactMap { $0.representedObject as? String }
                .filter { $0.hasPrefix(StatusItemController.overviewRowIdentifierPrefix) }
        }

        let original = rowIdentifiers()
        #expect(original.count >= 2)
        let draggedRow = try #require(menu.items.first {
            ($0.representedObject as? String) == original.first
        })
        let draggedView = try #require(draggedRow.view as? MenuRowContainerView)
        let drop = try #require(draggedView.rowPayload.onReorder)

        var rebuiltMenus: [NSMenu] = []
        controller._test_openMenuRebuildObserver = { rebuilt in
            rebuiltMenus.append(rebuilt)
        }
        defer { controller._test_openMenuRebuildObserver = nil }

        // Drop the first row at the bottom. The rebuilt row order decides each row's divider, so
        // the order alone covers "the last row has no divider, the one above it does".
        let dropped = Array(original.dropFirst()) + [original[0]]
        drop(dropped)
        Self.drainTracking()

        #expect(rebuiltMenus.count == 1)
        #expect(rebuiltMenus.first === menu)
        #expect(controller.settings.overviewRowOrderIDs == dropped)
        #expect(rowIdentifiers() == dropped)
        #expect(!controller.menuNeedsRefresh(menu))
    }

    private static func drainTracking() {
        CFRunLoopRunInMode(CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString), 0.1, true)
    }
}
