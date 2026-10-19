import AppKit
import CodexBarCore
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
        let labels = bar.subviews.compactMap { $0.accessibilityLabel() }
        #expect(labels.contains { $0.hasPrefix("About CodexBar") })
        let quitButton = try #require(bar.button(labeled: "Quit"))
        #expect(quitButton.isAccessibilityElement())
        #expect(quitButton.accessibilityRole() == .button)

        // Shortcuts are not carried by menu items anymore; the menu itself answers them.
        let hasShortcut = menu.items.contains { $0.keyEquivalent.isEmpty == false }
        #expect(hasShortcut == false)
        let statusMenu = try #require(menu as? StatusItemMenu)
        let refreshKey = try self.keyEvent("r")
        let settingsKey = try self.keyEvent(",")
        let quitKey = try self.keyEvent("q")
        #expect(statusMenu.performKeyEquivalent(with: refreshKey))
        #expect(statusMenu.performKeyEquivalent(with: settingsKey))
        #expect(statusMenu.performKeyEquivalent(with: quitKey))
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
        controller.updateMenuFooterBars()
        #expect(bar.isSpinning(systemImageName: symbol))

        controller.store.refreshingProviders.removeAll()
        controller.updateMenuFooterBars()
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
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).cgColor
        bar.layoutSubtreeIfNeeded()

        bar.setHovering(true, labeled: "Settings...")
        guard let path = ProcessInfo.processInfo.environment["CODEXBAR_MENU_FOOTER_PROOF"] else { return }
        let rep = try #require(self.bitmap(of: bar, scale: 2))
        let png = try #require(rep.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: path))
    }

    /// `dataWithPDF` drops layer backgrounds, so the menu colour is painted into the bitmap first.
    private func bitmap(of view: NSView, scale: CGFloat) -> NSBitmapImageRep? {
        let width = Int(view.bounds.width * scale)
        let height = Int(view.bounds.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context
        context?.cgContext.scaleBy(x: scale, y: scale)
        NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).setFill()
        view.bounds.fill()
        view.displayIgnoringOpacity(view.bounds, in: context!)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    @Test
    func `refresh icon turns about the centre of its button`() throws {
        let bar = MenuFooterBarView(width: 300, buttons: [
            MenuFooterButton(systemImageName: "arrow.clockwise", label: "Refresh") {},
        ])
        bar.layoutSubtreeIfNeeded()
        let button = try #require(bar.button(labeled: "Refresh"))
        button.layoutSubtreeIfNeeded()
        let layer = try #require(bar.iconLayer(systemImageName: "arrow.clockwise"))
        bar.setSpinning(true, systemImageName: "arrow.clockwise")
        #expect(bar.isSpinning(systemImageName: "arrow.clockwise"))
        // A rotation keeps the anchor point fixed, so the anchor has to be the button's centre.
        #expect(layer.anchorPoint == CGPoint(x: 0.5, y: 0.5))
        #expect(abs(layer.position.x - button.bounds.midX) < 0.5)
        #expect(abs(layer.position.y - button.bounds.midY) < 0.5)
        #expect(abs(layer.frame.midX - button.bounds.midX) < 0.5)
        bar.setSpinning(false, systemImageName: "arrow.clockwise")
        #expect(!bar.isSpinning(systemImageName: "arrow.clockwise"))
        #expect(abs(layer.frame.midY - button.bounds.midY) < 0.5)
    }

    /// Samples where the spinning refresh icon is drawn, in a real window, when CODEXBAR_FOOTER_SPIN_SAMPLE
    /// is set; it needs a window server, so it stays out of the default run.
    @Test
    func `spinning refresh icon stays centred in a window`() throws {
        guard ProcessInfo.processInfo.environment["CODEXBAR_FOOTER_SPIN_SAMPLE"] != nil else { return }
        let bar = MenuFooterBarView(width: 300, buttons: [
            MenuFooterButton(systemImageName: "arrow.clockwise", label: "Refresh") {},
        ])
        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 300, height: MenuFooterBarView.barHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false)
        window.contentView = bar
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        bar.layoutSubtreeIfNeeded()
        let button = try #require(bar.button(labeled: "Refresh"))
        let layer = try #require(bar.iconLayer(systemImageName: "arrow.clockwise"))
        bar.setSpinning(true, systemImageName: "arrow.clockwise")
        var samples: [CGPoint] = []
        let start = Date()
        while Date().timeIntervalSince(start) < 0.6 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            if let presentation = layer.presentation() {
                samples.append(CGPoint(x: presentation.frame.midX, y: presentation.frame.midY))
            }
        }
        bar.setSpinning(false, systemImageName: "arrow.clockwise")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let rest = CGPoint(x: layer.frame.midX, y: layer.frame.midY)
        print("SPIN_SAMPLES button=\(button.bounds.size) centre=\(samples) rest=\(rest)")
        #expect(!samples.isEmpty)
        for sample in samples {
            #expect(abs(sample.x - button.bounds.midX) <= 0.5)
            #expect(abs(sample.y - button.bounds.midY) <= 0.5)
        }
        #expect(abs(rest.x - button.bounds.midX) <= 0.5 && abs(rest.y - button.bounds.midY) <= 0.5)
    }

    @Test
    func `a menu rebuild keeps the footer bar and its spinning refresh icon`() throws {
        let settings = self.makeSettings()
        settings.refreshFrequency = .manual
        settings.mergeIcons = false
        enableTestProviders([.codex], settings: settings)
        let controller = self.makeController(settings: settings)
        let menu = controller.makeMenu(for: .codex)
        controller.menuWillOpen(menu)
        defer { controller.menuDidClose(menu) }

        let footerItem = try #require(menu.items.first { $0.view is MenuFooterBarView })
        let bar = try #require(footerItem.view as? MenuFooterBarView)
        // A refresh is in flight for the whole rebuild, so every footer bar keeps spinning.
        let gate = RefreshGate()
        controller.manualRefreshTasks[.global] = Task { await gate.wait() }
        defer {
            gate.resume()
            controller.manualRefreshTasks[.global] = nil
        }
        controller.updateMenuFooterBars()
        let spin = bar.iconLayer(systemImageName: "arrow.clockwise")?.animation(forKey: "footerSpin")

        let shapes = controller.menuContentShapes(in: menu, fromIndex: 0)
        let scratch = controller.makeMenu(for: .codex)
        controller.menuWillOpen(scratch)
        controller.menuDidClose(scratch)
        let scratchBar = try #require(scratch.items.first { $0.view is MenuFooterBarView }?.view)
        controller.reconcileMenuContent(menu, fromIndex: 0, shapes: shapes, with: scratch)

        let rebuiltItem = try #require(menu.items.first { $0.representedObject as? String == "menuFooterBar" })
        #expect(rebuiltItem.view === bar)
        #expect(rebuiltItem.view !== scratchBar)
        #expect(bar.isSpinning(systemImageName: "arrow.clockwise"))
        #expect(bar.iconLayer(systemImageName: "arrow.clockwise")?.animation(forKey: "footerSpin") === spin)
        #expect(!controller.menuFooterBars.contains(scratchBar as? MenuFooterBarView))
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
