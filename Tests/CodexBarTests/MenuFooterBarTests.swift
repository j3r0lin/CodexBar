import AppKit
import Testing
@testable import CodexBar

@MainActor
struct MenuFooterBarTests {
    @Test
    func `meta actions collapse into one icon bar`() throws {
        let settings = self.makeSettings()
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        enableTestProviders([.codex], settings: settings)

        let controller = self.makeController(settings: settings)
        let menu = controller.makeMenu(for: .codex)
        controller.menuWillOpen(menu)

        let titles = Set(menu.items.map(\.title))
        #expect(!titles.contains("Refresh"))
        #expect(!titles.contains("Settings..."))
        #expect(!titles.contains("Quit"))
        #expect(titles.filter { $0.hasPrefix("About CodexBar") }.isEmpty)

        let bars = menu.items.compactMap { $0.view as? MenuFooterBarView }
        let bar = try #require(bars.first)
        #expect(bars.count == 1)
        #expect(bar.button(labeled: "Refresh") != nil)
        #expect(bar.button(labeled: "Settings...") != nil)
        #expect(bar.button(labeled: "Quit") != nil)
        let about = try #require(menu.items.last?.view?.subviews.first { $0.accessibilityLabel()?.hasPrefix("About") })
        #expect(about.accessibilityLabel()?.contains("About CodexBar") == true)

        // Shortcuts are not carried by menu items anymore; the menu itself answers them.
        #expect(menu.items.allSatisfy { $0.keyEquivalent.isEmpty })
        let statusMenu = try #require(menu as? StatusItemMenu)
        #expect(statusMenu.performKeyEquivalent(with: self.keyEvent("r")))
        #expect(statusMenu.performKeyEquivalent(with: self.keyEvent(",")))
        #expect(statusMenu.performKeyEquivalent(with: self.keyEvent("q")))
    }

    @Test
    func `refresh icon spins while a refresh is in flight`() throws {
        let settings = self.makeSettings()
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        enableTestProviders([.codex], settings: settings)

        let controller = self.makeController(settings: settings)
        let menu = controller.makeMenu(for: .codex)
        controller.menuWillOpen(menu)
        let bar = try #require(menu.items.compactMap { $0.view as? MenuFooterBarView }.first)
        let symbol = try #require(MenuDescriptor.MenuAction.refresh.systemImageName)

        #expect(!bar.isSpinning(systemImageName: symbol))
        controller.store.refreshingProviders.insert(.codex)
        controller.updatePersistentRefreshItemsEnabled()
        #expect(bar.isSpinning(systemImageName: symbol))

        controller.store.refreshingProviders.removeAll()
        controller.updatePersistentRefreshItemsEnabled()
        #expect(!bar.isSpinning(systemImageName: symbol))
    }

    @Test
    func `pressing the refresh button starts a refresh`() async throws {
        let settings = self.makeSettings()
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        enableTestProviders([.codex], settings: settings)

        let controller = self.makeController(settings: settings)
        let menu = try #require(controller.makeMenu(for: .codex) as? StatusItemMenu)
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        let gate = RefreshGate()
        controller._test_manualRefreshOperation = { await gate.wait() }
        let bar = try #require(menu.items.compactMap { $0.view as? MenuFooterBarView }.first)
        let refresh = try #require(bar.button(labeled: "Refresh"))
        #expect(refresh.accessibilityPerformPress())
        for _ in 0..<20 where controller.manualRefreshTasks[.provider(.codex)] == nil {
            await Task.yield()
        }
        let task = try #require(controller.manualRefreshTasks[.provider(.codex)])
        gate.resume()
        await task.value
        #expect(controller.manualRefreshTasks[.provider(.codex)] == nil)
    }

    @Test
    func `bar renders on the dark menu background`() throws {
        let bar = MenuFooterBarView(width: 310, buttons: [
            MenuFooterButton(systemImageName: "arrow.clockwise", label: "Refresh", action: {}),
            MenuFooterButton(systemImageName: "gearshape", label: "Settings...", action: {}),
            MenuFooterButton(systemImageName: "info.circle", label: "About CodexBar (v1.2.3)", action: {}),
            MenuFooterButton(systemImageName: "power", label: "Quit", action: {}),
        ])
        bar.appearance = NSAppearance(named: .darkAqua)
        bar.layoutSubtreeIfNeeded()

        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_MENU_FOOTER_PROOF"] else { return }
        let rep = try #require(self.bitmap(of: bar))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: path))
    }

    private func bitmap(of view: NSView) -> NSBitmapImageRep? {
        guard let data = view.dataWithPDF(inside: view.bounds) as Data? else { return nil }
        guard let image = NSImage(data: data) else { return nil }
        return NSBitmapImageRep(data: image.tiffRepresentation ?? Data())
    }

    private func keyEvent(_ characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 0))
    }

    private func makeSettings() -> SettingsStore {
        let suite = "MenuFooterBarTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func makeController(settings: SettingsStore) -> StatusItemController {
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        return StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
    }
}

private final class RefreshGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            self.lock.lock()
            if self.resumed {
                self.lock.unlock()
                continuation.resume()
            } else {
                self.waiters.append(continuation)
                self.lock.unlock()
            }
        }
    }

    func resume() {
        self.lock.lock()
        self.resumed = true
        let waiters = self.waiters
        self.waiters = []
        self.lock.unlock()
        for waiter in waiters {
            waiter.resume()
        }
    }
}
