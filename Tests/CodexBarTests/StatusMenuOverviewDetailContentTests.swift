import AppKit
import CodexBarCore
import SwiftUI
import Testing
import Vision
@testable import CodexBar

extension StatusMenuTests {
    private func makeOverviewController(
        providers: [UsageProvider],
        rendersCards: Bool = false,
        configure: (SettingsStore) -> Void = { _ in }) -> (StatusItemController, UsageStore, SettingsStore)
    {
        self.disableMenuCardsForTesting()
        StatusItemController.menuCardRenderingEnabled = rendersCards
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = providers.first?.instanceID
        settings.mergedMenuLastSelectedWasOverview = true
        enableTestProviders(Set(providers), settings: settings)
        configure(settings)
        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        return (controller, store, settings)
    }

    private func openDetail(of provider: UsageProvider, in menu: NSMenu) throws -> NSMenu {
        let row = try #require(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-\(provider.rawValue)"
        })
        let detail = try #require(row.submenu)
        detail.delegate?.menuNeedsUpdate?(detail)
        return detail
    }

    /// Text a person reads in the rendered card, found by recognising the drawn pixels.
    @MainActor
    private func renderedText(of view: some View, width: CGFloat) throws -> String {
        let hosting = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        hosting.appearance = NSAppearance(named: .darkAqua)
        let height = hosting.fittingSize.height
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)
        hosting.layoutSubtreeIfNeeded()
        let rep = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let cgImage = try #require(rep.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        return lines.joined(separator: "\n")
    }

    @Test
    func `detail actions open the provider whose detail they sit in`() throws {
        let (controller, _, settings) = self.makeOverviewController(providers: [.claude, .codex, .kimi]) {
            $0.providerChangelogLinksEnabled = true
        }
        defer { controller.releaseStatusItemsForTesting() }
        _ = settings
        // The global memory of the last provider-page selection points at another provider.
        controller.lastMenuProvider = UsageProvider.codex.instanceID

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        for provider in [UsageProvider.claude, .kimi] {
            let detail = try self.openDetail(of: provider, in: menu)
            let actions = [
                controller.selector(for: .dashboard, provider: provider).0,
                controller.selector(for: .statusPage, provider: provider).0,
                controller.selector(for: .changelog, provider: provider).0,
            ]
            let items = detail.items.filter { item in item.action.map(actions.contains) == true }
            #expect(items.contains { $0.action == actions[0] })
            // Only some providers publish a status page.
            if provider == .claude {
                #expect(items.contains { $0.action == actions[1] })
            }
            for item in items {
                #expect(controller.actionProvider(for: item) == provider)
            }
        }
    }

    @Test
    func `codex accounts can be switched from the merged menu detail`() throws {
        let (controller, _, settings) = self.makeOverviewController(providers: [.codex, .claude]) {
            $0.multiAccountMenuLayout = .segmented
        }
        defer { controller.releaseStatusItemsForTesting() }
        let managed = try ManagedCodexAccount(
            id: #require(UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-111111111111")),
            email: "managed@example.com",
            managedHomePath: "/tmp/managed-home",
            createdAt: 1,
            updatedAt: 2,
            lastAuthenticatedAt: 2)
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManagedCodexAccountStore(fileURL: storeURL).storeAccounts(ManagedCodexAccountSet(
            version: FileManagedCodexAccountStore.currentVersion,
            accounts: [managed]))
        defer {
            settings._test_managedCodexAccountStoreURL = nil
            settings._test_liveSystemCodexAccount = nil
            try? FileManager.default.removeItem(at: storeURL)
        }
        settings._test_managedCodexAccountStoreURL = storeURL
        settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
            email: "live@example.com",
            codexHomePath: "/Users/test/.codex",
            observedAt: Date())
        settings.codexActiveSource = .liveSystem
        _ = settings.codexVisibleAccountProjection

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let codexDetail = try self.openDetail(of: .codex, in: menu)
        #expect(codexDetail.items.contains { $0.view is CodexAccountSwitcherView })
        let claudeDetail = try self.openDetail(of: .claude, in: menu)
        #expect(!claudeDetail.items.contains { $0.view is CodexAccountSwitcherView })
    }

    @Test
    func `detail card shows provider details when the provider has no usage windows`() throws {
        let (controller, store, _) = self.makeOverviewController(providers: [.zai, .claude])
        defer { controller.releaseStatusItemsForTesting() }
        let detail = try ProviderDetailSection(title: "Quota details", rows: [
            .init(label: "MCP quota", value: "50% used", secondaryValue: "100 limit - 50 remaining"),
        ])
        store._setSnapshotForTesting(
            UsageSnapshot(primary: nil, secondary: nil, details: [detail], updatedAt: Date()),
            provider: .zai)

        let text = try self.renderedText(
            of: AccountUsageDetailView(
                provider: .zai,
                providerName: "Z.ai",
                snapshot: store.snapshot(for: .zai),
                model: store.menuCardModel(for: .zai)),
            width: AccountUsageDetailView.defaultWidth)
        #expect(text.contains("MCP quota"))
        #expect(text.contains("50% used"))
        #expect(!text.contains("No data"))
    }

    @Test
    func `detail card keeps old usage and marks a failed refresh`() throws {
        let (controller, store, _) = self.makeOverviewController(providers: [.zai, .claude])
        defer { controller.releaseStatusItemsForTesting() }
        let now = Date()
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 42, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: now.addingTimeInterval(-3600)),
            provider: .zai)
        store._setErrorForTesting("Session expired", provider: .zai)

        let text = try self.renderedText(
            of: AccountUsageDetailView(
                provider: .zai,
                providerName: "Z.ai",
                snapshot: store.snapshot(for: .zai),
                model: store.menuCardModel(for: .zai)),
            width: AccountUsageDetailView.defaultWidth)
        #expect(text.contains("42%"))
        #expect(text.contains("Session expired") || text.lowercased().contains("expired"))
    }

    @Test
    func `detail card lists every reset credit of a magpie account`() throws {
        let now = Date()
        let credits = MagpieResetCredits(expirations: [
            now.addingTimeInterval(86400),
            now.addingTimeInterval(3 * 86400),
            nil,
        ])
        let view = AccountUsageDetailView(
            provider: .codex,
            providerName: "Codex",
            snapshot: nil,
            namedWindows: [],
            now: now,
            resetCredits: credits)
        #expect(view.resetCreditsPresentation?.items.count == 3)
        let text = try self.renderedText(of: view, width: AccountUsageDetailView.defaultWidth)
        #expect(text.contains("3"))
        #expect(!text.contains("No data"))
        let without = AccountUsageDetailView(provider: .codex, providerName: "Codex", snapshot: nil, now: now)
        #expect(without.resetCreditsPresentation == nil)
    }

    @Test
    func `detail card shows codex credits next to the usage windows`() throws {
        let metadata = try #require(ProviderDefaults.metadata[.codex])
        let now = Date()
        let model = UsageMenuCardView.Model.make(.init(
            provider: .codex,
            metadata: metadata,
            snapshot: nil,
            credits: CreditsSnapshot(
                remaining: 1234,
                events: [],
                updatedAt: now,
                creditsAvailable: true,
                balanceIsWorkspace: true),
            creditsError: nil,
            dashboardError: nil,
            tokenSnapshot: nil,
            tokenError: nil,
            account: AccountInfo(email: nil, plan: nil),
            isRefreshing: false,
            lastError: nil,
            usageBarsShowUsed: true,
            resetTimeDisplayStyle: .countdown,
            tokenCostUsageEnabled: false,
            showOptionalCreditsAndExtraUsage: true,
            hidePersonalInfo: false,
            now: now))
        let creditsText = try #require(model.creditsText)

        let text = try self.renderedText(
            of: AccountUsageDetailView(provider: .codex, providerName: "Codex", snapshot: nil, model: model),
            width: AccountUsageDetailView.defaultWidth)
        #expect(text.contains("1,234") || text.contains("1234") || text.contains(creditsText.prefix(4)))
        #expect(!text.contains("No data"))
    }

    @Test
    func `detail windows follow the hidden usage items and the optional usage switch`() {
        let now = Date()
        let spark = NamedRateWindow(
            id: "codex-spark",
            title: "GPT-5.3-Codex-Spark",
            window: RateWindow(usedPercent: 33, windowMinutes: 300, resetsAt: nil, resetDescription: nil))
        let snapshot = UsageSnapshot(
            primary: RateWindow(usedPercent: 10, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: RateWindow(usedPercent: 20, windowMinutes: 7 * 1440, resetsAt: nil, resetDescription: nil),
            extraRateWindows: [spark],
            updatedAt: now)
        let (controller, store, settings) = self.makeOverviewController(providers: [.codex, .claude])
        defer { controller.releaseStatusItemsForTesting() }
        store._setSnapshotForTesting(snapshot, provider: .codex)

        func titles() -> [String] {
            AccountUsageDetailView.blocks(of: snapshot, model: store.menuCardModel(for: .codex)).map(\.title)
        }
        #expect(titles().contains("GPT-5.3-Codex-Spark"))

        settings.codexSparkUsageVisible = false
        #expect(!titles().contains("GPT-5.3-Codex-Spark"))
        #expect(titles().count == 2)

        settings.codexSparkUsageVisible = true
        settings.showOptionalCreditsAndExtraUsage = false
        #expect(!titles().contains("GPT-5.3-Codex-Spark"))
    }

    @Test
    func `magpie detail blocks use the row's window labels and keep reset times`() {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let windows = [
            OverviewUsageRow.NamedWindow(window: MagpieQuotaWindow(name: "Month", usedPercent: 62, resetsAt: reset)),
            OverviewUsageRow.NamedWindow(window: MagpieQuotaWindow(name: "Daily", usedPercent: 30, resetsAt: nil)),
        ]
        let now = reset.addingTimeInterval(-86400 * 10)
        let blocks = AccountUsageDetailView.blocks(of: windows, now: now)
        #expect(blocks.map(\.title) == windows.map(\.label))
        #expect(blocks.map(\.used) == [62, 30])
        #expect(blocks[0].resetText == AccountUsageDetailView.resetText(reset, now: now))
        #expect(blocks[1].resetText == nil)
    }

    @Test
    func `overview row height follows a row going from usage to error and back`() throws {
        let previous = StatusItemController.menuCardRenderingEnabled
        defer { StatusItemController.menuCardRenderingEnabled = previous }
        let (controller, store, _) = self.makeOverviewController(providers: [.zai, .claude], rendersCards: true)
        defer { controller.releaseStatusItemsForTesting() }

        let usage = UsageSnapshot(
            primary: RateWindow(usedPercent: 12, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
            secondary: nil,
            updatedAt: Date())
        let longError = "The provider could not refresh usage because the saved session has expired. "
            + "Sign in again to continue."

        let menu = controller.makeMenu()
        func rowHeight() throws -> CGFloat {
            controller.menuWillOpen(menu)
            defer { controller.menuDidClose(menu) }
            let row = try #require(menu.items.first { ($0.representedObject as? String) == "overviewRow-zai" })
            let view = try #require(row.view)
            view.layoutSubtreeIfNeeded()
            return view.frame.height
        }

        store._setErrorForTesting(nil, provider: .zai)
        store._setSnapshotForTesting(usage, provider: .zai)
        let normal = try rowHeight()

        store._setSnapshotForTesting(nil, provider: .zai)
        store._setErrorForTesting(longError, provider: .zai)
        let failed = try rowHeight()
        #expect(failed > normal)

        store._setErrorForTesting(nil, provider: .zai)
        store._setSnapshotForTesting(usage, provider: .zai)
        #expect(try rowHeight() == normal)
    }

    @Test
    func `detail leaves out the usage history chart when nothing was recorded`() throws {
        let (controller, store, _) = self.makeOverviewController(providers: [.codex, .claude], rendersCards: true)
        defer { controller.releaseStatusItemsForTesting() }
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 31, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: Date()),
            provider: .codex)

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let detail = try self.openDetail(of: .codex, in: menu)
        let chartID = StatusItemController.usageHistoryChartID
        #expect(!detail.items.contains { ($0.representedObject as? String) == chartID })
    }

    @Test
    func `status components link resolves to the provider of its submenu`() throws {
        let (controller, _, _) = self.makeOverviewController(providers: [.claude, .codex])
        defer { controller.releaseStatusItemsForTesting() }
        controller.lastMenuProvider = UsageProvider.codex.instanceID

        let submenu = NSMenu()
        _ = controller.appendStatusComponentsItem(to: submenu, provider: .claude, width: 300)
        let link = try #require(submenu.items.first {
            $0.action == #selector(StatusItemController.openStatusPageFromMenuItem(_:))
        })
        #expect(controller.statusPageProvider(for: link) == .claude)
    }

    @Test
    func `detail adds no usage history chart even when history was recorded`() throws {
        let (controller, store, _) = self.makeOverviewController(providers: [.opencodego, .codex], rendersCards: true)
        defer { controller.releaseStatusItemsForTesting() }
        let now = Date()
        store._setSnapshotForTesting(
            UsageSnapshot(
                primary: RateWindow(usedPercent: 20, windowMinutes: 300, resetsAt: nil, resetDescription: nil),
                secondary: nil,
                updatedAt: now),
            provider: .opencodego)
        store.planUtilizationHistory[UsageProvider.opencodego.instanceID] = PlanUtilizationHistoryBuckets(
            unscoped: [PlanUtilizationSeriesHistory(
                name: .session,
                windowMinutes: 300,
                entries: [PlanUtilizationHistoryEntry(
                    capturedAt: now.addingTimeInterval(-86400),
                    usedPercent: 40,
                    resetsAt: now.addingTimeInterval(-86400 + 3600))])])
        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let detail = try self.openDetail(of: .opencodego, in: menu)
        let ids = detail.items.compactMap { $0.representedObject as? String }
        #expect(!ids.contains(StatusItemController.usageHistoryChartID))
    }

    @Test
    func `each magpie account has an independent card without a group heading`() throws {
        let (controller, store, settings) = self.makeOverviewController(
            providers: [.claude, .codex],
            rendersCards: true)
        defer { controller.releaseStatusItemsForTesting() }
        store.magpieTransport = { _ in
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        }
        settings.magpieSourceEnabled = true
        let accounts = ["one", "two", "three"].enumerated().map { index, name in
            MagpieAccountSnapshot(
                id: ProviderAccountIdentity(source: "magpie", opaqueID: "claude:\(name)"),
                provider: MagpieProviderMapping.reference(for: "claude"),
                displayLabel: name,
                accountEmail: nil,
                ordinal: index + 1,
                windows: [MagpieQuotaWindow(name: "5 hours", usedPercent: 12, resetsAt: nil)],
                readAt: Date(),
                isActive: index == 0,
                error: nil)
        }
        store.magpieAccountSnapshots = accounts

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)
        let wholeRowSelections = try accounts.map { account in
            let item = try #require(menu.items.first {
                ($0.representedObject as? String) == "overviewRow-claude#\(account.id.opaqueID)"
            })
            return try #require((item.view as? MenuRowContainerView)?.rowPayload.selectsWholeRow)
        }
        #expect(wholeRowSelections.allSatisfy(\.self))
        #expect(!menu.items.contains { ($0.representedObject as? String)?.hasPrefix("overviewHeading-") == true })
    }
}
