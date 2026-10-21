import AppKit
import Foundation
import XCTest
@testable import CodexBar
@testable import CodexBarCore

/// Opt-in card-UI proof: pops the real merged Overview menu with synthetic magpie and native data,
/// then screenshots the live menu window and one detail submenu. Runs only when
/// CODEXBAR_CARD_UI_PROOF_DIR is set.
@MainActor
final class StatusMenuCardUINativeProofTests: XCTestCase {
    private enum Phase {
        case settleNow
        case captureNow
        case closing
    }

    // The timers below are @Sendable closures, so the menu tracking state they touch lives on
    // the (main-actor) test instance instead of being captured from the test method.
    private var phase: Phase = .settleNow
    private var settleTicks = 0
    private var detailTicks = 0
    private var proofMenu: NSMenu?
    private var detailMenu: NSMenu?
    private var proofDirectory: URL?

    func test_cardUIProof() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directoryPath = environment["CODEXBAR_CARD_UI_PROOF_DIR"] else {
            throw XCTSkip("Set CODEXBAR_CARD_UI_PROOF_DIR for the card UI proof.")
        }
        guard SettingsStore.isRunningTests,
              environment["CODEXBAR_SUPPRESS_TEST_KEYCHAIN_ACCESS"] == "1",
              environment[CodexCredentialFileAccess.isolationEnvironmentKey] == "1",
              environment["CODEXBAR_TEST_SESSION_FILE_ISOLATION"] == "1",
              environment["CODEXBAR_ALLOW_TEST_KEYCHAIN_ACCESS"] != "1",
              environment["CODEXBAR_TEST_CODEX_FILE_FIXTURES"] == nil
        else {
            return XCTFail("Native proof requires credential and session isolation.")
        }
        let directory = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fixture = try CodexWorkspacesNavigationFixture(userDefaults: InMemoryUserDefaults())
        defer { fixture.cleanup() }
        Self.seedCardUI(in: fixture)

        let oldRendering = StatusItemController.menuCardRenderingEnabled
        let oldRefresh = StatusItemController.menuRefreshEnabled
        StatusItemController.menuCardRenderingEnabled = true
        StatusItemController.setMenuRefreshEnabledForTesting(true)
        defer {
            StatusItemController.menuCardRenderingEnabled = oldRendering
            StatusItemController.setMenuRefreshEnabledForTesting(oldRefresh)
        }
        let controller = fixture.makeController()
        defer { controller.releaseStatusItemsForTesting() }
        let menu = try XCTUnwrap(controller.makeMenu() as? StatusItemMenu)
        controller.mergedMenu = menu
        self.proofMenu = menu
        self.proofDirectory = directory
        self.phase = .settleNow
        self.settleTicks = 0
        self.detailTicks = 0

        let application = NSApplication.shared
        guard application.delegate == nil else {
            return XCTFail("Native proof requires a standalone test application.")
        }
        let oldPolicy = application.activationPolicy()
        let previousApplication = NSWorkspace.shared.frontmostApplication
        let host = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        host.title = "CodexBar Card UI Proof"
        host.isReleasedWhenClosed = false
        host.center()
        defer {
            host.close()
            _ = application.setActivationPolicy(oldPolicy)
            if NSWorkspace.shared.frontmostApplication?.processIdentifier
                == ProcessInfo.processInfo.processIdentifier
            {
                previousApplication?.activate()
            }
        }
        XCTAssertTrue(application.setActivationPolicy(.regular))
        application.finishLaunching()
        application.activate(ignoringOtherApps: true)
        host.makeKeyAndOrderFront(nil)

        // Common-mode timer: it keeps firing while the menu tracks in event-tracking mode.
        // Target/selector form: a Timer block is @Sendable and may not capture the test state.
        let timer = Timer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(self.tickOverviewCapture),
            userInfo: nil,
            repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        defer { timer.invalidate() }

        // Blocking: returns once the state machine cancels tracking after the third capture.
        menu.popUp(positioning: nil, at: NSPoint(x: 20, y: 120), in: host.contentView)
        Self.recordDiagnostic(
            "popUp returned: phase=\(self.phase) ticks=\(self.settleTicks) "
                + "items=\(menu.items.count) views=\(menu.items.count { $0.view != nil })",
            into: directory)
        let ids = menu.items.compactMap { $0.representedObject as? String }
        Self.recordDiagnostic("ids=\(ids.joined(separator: ","))", into: directory)
        Self.recordDiagnostic(
            "magpieAccounts=\(fixture.store.magpieAccountSnapshots.count) "
                + "overview=\(fixture.store.magpieOverviewSnapshots.count)",
            into: directory)
        let rowsNow = controller.overviewUsageRows(visibleProviders: [.claude, .codex, .grok, .kimi])
        Self.recordDiagnostic(
            "rows=\(rowsNow.map { $0.groupKey + ($0.accountID.map { "#" + $0.opaqueID } ?? "") })",
            into: directory)

        // Detail submenu: captured in its own tracking session, again from a common-mode timer.
        let row = try XCTUnwrap(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-codex"
        })
        let detail = try XCTUnwrap(row.submenu)
        self.detailMenu = detail
        let detailTimer = Timer(
            timeInterval: 0.25,
            target: self,
            selector: #selector(self.tickDetailCapture),
            userInfo: nil,
            repeats: true)
        RunLoop.main.add(detailTimer, forMode: .common)
        defer { detailTimer.invalidate() }
        detail.popUp(positioning: nil, at: NSPoint(x: 120, y: 120), in: host.contentView)

        for name in ["cardui-overview", "cardui-detail"] {
            let png = directory.appendingPathComponent("\(name).png")
            XCTAssertTrue(FileManager.default.fileExists(atPath: png.path), "missing \(name).png")
        }
    }

    /// One step of the capture state machine: settle, capture, close.
    @objc private func tickOverviewCapture() {
        guard let menu = self.proofMenu,
              let directory = self.proofDirectory
        else { return }
        let menuWindow = menu.items.compactMap { $0.view?.window }.first
        switch self.phase {
        case .settleNow:
            guard menuWindow != nil else { return }
            self.settleTicks += 1
            if self.settleTicks >= 4 { self.phase = .captureNow }
        case .captureNow:
            Self.capture(window: menuWindow, name: "cardui-overview", into: directory)
            self.phase = .closing
            menu.cancelTracking()
        case .closing:
            break
        }
    }

    @objc private func tickDetailCapture() {
        guard let detail = self.detailMenu, let directory = self.proofDirectory else { return }
        self.detailTicks += 1
        guard self.detailTicks >= 4 else { return }
        let window = detail.items.compactMap { $0.view?.window }.first
        Self.capture(window: window, name: "cardui-detail", into: directory)
        self.detailMenu = nil
        detail.cancelTracking()
    }

    /// Captures the menu window in-process: `screencapture -l` runs as a separate process and the
    /// window belongs to the test runner, so without a Screen Recording grant it fails with "could
    /// not create image from window". A process may always read its own windows.
    private static func capture(window: NSWindow?, name: String, into directory: URL) {
        guard let window else {
            self.recordDiagnostic("capture \(name): no window", into: directory)
            return
        }
        let url = directory.appendingPathComponent("\(name).png")
        if let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(window.windowNumber),
            [.boundsIgnoreFraming, .bestResolution]),
            let bitmap = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        {
            do {
                try bitmap.write(to: url)
                Self.recordDiagnostic("capture \(name): cgwindowlist ok", into: directory)
                return
            } catch {
                Self.recordDiagnostic("capture \(name): write failed: \(error)", into: directory)
            }
        } else {
            Self.recordDiagnostic("capture \(name): CGWindowListCreateImage returned nil", into: directory)
        }
    }

    private static func recordDiagnostic(_ line: String, into directory: URL) {
        let file = directory.appendingPathComponent("diagnostics.txt")
        let data = (line + "\n").data(using: .utf8) ?? Data()
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }

    /// Synthetic mirror of the reference mockup: three magpie Claude accounts, native Codex, Grok
    /// with only a weekly window, Kimi Code, and a magpie opencode-go account with only an error.
    private static func seedCardUI(in fixture: CodexWorkspacesNavigationFixture) {
        let now = Date()
        for provider in [UsageProvider.claude, .codex, .grok, .kimi] {
            fixture.settings.setProviderEnabled(
                provider: provider,
                metadata: ProviderDescriptorRegistry.descriptor(for: provider).metadata,
                enabled: true)
        }
        fixture.settings.mergeIcons = true
        fixture.settings.mergedMenuLastSelectedWasOverview = true

        func window(_ minutes: Int?, _ used: Double, _ resetMinutes: Double?) -> RateWindow {
            RateWindow(
                usedPercent: used,
                windowMinutes: minutes,
                resetsAt: resetMinutes.map { now.addingTimeInterval($0 * 60) },
                resetDescription: nil)
        }
        // A transport that never completes keeps the synthetic snapshots in place.
        fixture.store.magpieTransport = { _ in
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        }
        fixture.settings.magpieSourceEnabled = true
        fixture.settings.magpieTakeoverWireIDs = ["claude", "opencode-go"]
        // Reconcile before seeding: the first reconcile on menu open would otherwise see the
        // switch flip and wipe the snapshots we are about to plant. It also strips native
        // snapshots from every mapped provider, so the native seeds come after it.
        fixture.store.reconcileMagpieSourceConfiguration()
        fixture.store._setSnapshotForTesting(
            UsageSnapshot(
                primary: window(300, 10, 236),
                secondary: window(10080, 52, 5 * 1440 + 15 * 60),
                updatedAt: now),
            provider: .codex)
        fixture.store._setSnapshotForTesting(
            UsageSnapshot(
                primary: nil,
                secondary: window(10080, 92, 3 * 1440 + 14 * 60),
                updatedAt: now),
            provider: .grok)
        fixture.store._setSnapshotForTesting(
            UsageSnapshot(
                primary: window(300, 11, 62),
                secondary: window(10080, 50, 2 * 1440 + 21 * 60),
                updatedAt: now),
            provider: .kimi)
        func account(
            _ opaque: String,
            _ label: String,
            _ ordinal: Int,
            windows: [MagpieQuotaWindow],
            error: String? = nil) -> MagpieAccountSnapshot
        {
            MagpieAccountSnapshot(
                id: ProviderAccountIdentity(source: "magpie", opaqueID: opaque),
                provider: MagpieProviderMapping.reference(
                    for: opaque.split(separator: ":").first.map(String.init) ?? opaque),
                displayLabel: label,
                accountEmail: nil,
                ordinal: ordinal,
                windows: windows,
                readAt: now,
                isActive: ordinal == 1,
                error: error)
        }
        fixture.store.magpieAccountSnapshots = [
            account("claude:claude", "claude", 1, windows: [
                MagpieQuotaWindow(name: "5 hours", usedPercent: 22, resetsAt: now.addingTimeInterval(138 * 60)),
                MagpieQuotaWindow(
                    name: "7 days",
                    usedPercent: 10,
                    resetsAt: now.addingTimeInterval(6 * 86400 + 4 * 3600)),
            ]),
            account("claude:claude-1", "claude-1", 2, windows: [
                MagpieQuotaWindow(name: "5 hours", usedPercent: 12, resetsAt: now.addingTimeInterval(188 * 60)),
                MagpieQuotaWindow(
                    name: "7 days",
                    usedPercent: 22,
                    resetsAt: now.addingTimeInterval(5 * 86400 + 21 * 3600)),
            ]),
            account("claude:claude-2", "claude-2", 3, windows: [
                MagpieQuotaWindow(name: "5 hours", usedPercent: 0, resetsAt: nil),
                MagpieQuotaWindow(name: "7 days", usedPercent: 98, resetsAt: now.addingTimeInterval(248 * 60)),
            ]),
            account("opencode-go:main", "main", 1, windows: [], error: "No session cookies found"),
        ]
    }
}
