import AppKit
import CodexBarCore

extension StatusItemController {
    /// Hover submenu of an Overview row: the shared usage detail, a Claude refresh item on magpie rows,
    /// then the provider's cost or credits chart and its own actions. The chart and actions are built on
    /// first open so unopened rows stay cheap. Magpie rows never build them: a magpie account holds no
    /// native cost or provider actions of its own.
    func makeOverviewDetailSubmenu(
        row: OverviewUsageRow,
        width: CGFloat) -> NSMenu
    {
        let submenu = OverviewDetailMenu(controller: self) { [weak self] submenu in
            guard let self else { return }
            if !row.isMagpie, let provider = row.nativeProvider, let model = row.model {
                let chartID = self.appendOverviewRowChart(
                    to: submenu,
                    provider: provider,
                    model: model,
                    width: width)
                self.appendOverviewRowActions(to: submenu, provider: provider, width: width, inlineChartID: chartID)
            }
            self.appendScheduledResetSourceItem(to: submenu, row: row)
        }
        submenu.autoenablesItems = false
        submenu.minimumWidth = width
        submenu.appearance = StatusMenuAppearance.menuAppearance
        let now = Date()
        submenu.addItem(self.makeMenuCardItem(
            AccountUsageDetailView(
                provider: row.nativeProvider,
                providerName: row.providerName,
                accountName: row.accountName,
                snapshot: row.snapshot,
                namedWindows: row.namedWindows,
                errorText: row.isMagpie ? row.detailErrorText : nil,
                width: width,
                model: row.isMagpie ? nil : row.model,
                now: now,
                readAt: row.readAt,
                display: self.overviewDisplayOptions(provider: row.nativeProvider),
                hiddenItemIDs: row.nativeProvider.map { self.settings.hiddenUsageItemIDs(for: $0) } ?? [],
                isStale: row.isStale(
                    now: now,
                    threshold: OverviewUsageRow.staleThreshold(for: self.settings.refreshFrequency))),
            id: "overviewDetail-\(row.providerName)" + (row.accountName.map { "-\($0)" } ?? ""),
            width: width,
            // The pool holds the parent menu's row views; a detail card built first would take one of them.
            recyclesView: false))
        // Provider-specific by design: Claude retains its existing per-account refresh action.
        if row.isMagpie, row.nativeProvider == .claude, let accountID = row.accountID {
            submenu.addItem(.separator())
            submenu.addItem(self.makeRefreshClaudeAccountItem(accountID))
        }
        return submenu
    }

    /// Opens the announcement behind the row's scheduled-reset badge; built with the submenu's other
    /// lazy content, so the reset shown is the one current when the submenu opens.
    private func appendScheduledResetSourceItem(to submenu: NSMenu, row: OverviewUsageRow) {
        // Provider-specific by design: codex-resets.com only tracks Codex, native or via magpie.
        guard row.nativeProvider == .codex,
              let reset = self.store.visibleCodexScheduledReset(now: Date()), let sourceURL = reset.sourceURL
        else { return }
        if !submenu.items.isEmpty { submenu.addItem(.separator()) }
        submenu.addItem(self.makeScheduledResetSourceItem(reset.scheduledFor, sourceURL: sourceURL))
    }

    private func makeScheduledResetSourceItem(_ date: Date, sourceURL: URL) -> NSMenuItem {
        let item = NSMenuItem(
            title: L("Scheduled reset before %@", date.formatted(.dateTime.weekday(.abbreviated).hour().minute())),
            action: #selector(self.openScheduledResetSource(_:)),
            keyEquivalent: "")
        item.target = self
        item.representedObject = sourceURL
        return item
    }

    @objc private func openScheduledResetSource(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL, url.scheme?.lowercased() == "https" else { return }
        NSWorkspace.shared.open(url)
    }

    /// Appends the row's cost, credits or storage chart inline and returns its chart identifier, or nil when
    /// there is none. The usage-history chart stays out: the detail card's windows already cover usage.
    private func appendOverviewRowChart(
        to submenu: NSMenu,
        provider: UsageProvider,
        model: UsageMenuCardView.Model,
        width: CGFloat) -> String?
    {
        guard let chartMenu = self.makeOverviewRowSubmenu(
            provider: provider,
            model: model,
            width: width)
        else { return nil }
        self.hydrateHostedSubviewMenuIfNeeded(chartMenu, width: width)
        var chartItems = chartMenu.items
        while chartItems.last?.isSeparatorItem == true {
            chartItems.removeLast()
        }
        guard chartItems.contains(where: { $0.identifier != Self.hostedSubviewUnavailableItemID }) else { return nil }
        chartMenu.removeAllItems()
        submenu.addItem(.separator())
        chartItems.forEach(submenu.addItem)
        return chartItems.first?.representedObject as? String
    }

    /// Appends what the removed provider page offered beyond its usage: account switchers, OpenAI
    /// web submenus, Buy Credits, and the provider's contextual actions (login repair, dashboard, status).
    private func appendOverviewRowActions(
        to submenu: NSMenu,
        provider: UsageProvider,
        width: CGFloat,
        inlineChartID: String?)
    {
        let extras = NSMenu()
        extras.autoenablesItems = false
        extras.minimumWidth = width
        self.addCodexAccountSwitcherIfNeeded(
            to: extras,
            display: self.codexAccountMenuDisplay(for: provider),
            width: width,
            captureMenu: submenu)
        self.addTokenAccountSwitcherIfNeeded(
            to: extras,
            display: self.tokenAccountMenuDisplay(for: provider),
            width: width,
            captureMenu: submenu)
        // Provider-specific by design: claude-swap account switching lives on the Claude row.
        if provider == .claude, !self.claudeAccountTabsEnabled {
            let display = self.claudeSwapAccountMenuDisplay()
            if display.showsSwitcher {
                self.addClaudeSwapAccountSwitcher(display, to: extras, captureMenu: submenu, width: width)
            }
        }
        let web = self.openAIWebContext(currentProvider: provider, showAllAccounts: false)
        if web.hasUsageBreakdown {
            self.addUsageBreakdownSubmenu(to: extras)
        }
        if web.hasCreditsHistory {
            self.addCreditsHistorySubmenu(to: extras)
        }
        if web.hasCostHistory, inlineChartID != Self.costHistoryChartID {
            self.addCostHistorySubmenu(to: extras, provider: provider)
        }
        if web.canShowBuyCredits {
            extras.addItem(self.makeBuyCreditsItem())
        }
        while extras.items.last?.isSeparatorItem == true {
            extras.removeItem(at: extras.items.count - 1)
        }
        if !extras.items.isEmpty {
            let items = extras.items
            extras.removeAllItems()
            submenu.addItem(.separator())
            items.forEach(submenu.addItem)
        }

        let sections = self.makeMenuDescriptor(provider: provider, includeContextualActions: true)
            .sections
            .filter { $0.isContextual && $0.entries.contains(where: \.isActionable) }
        guard !sections.isEmpty else { return }
        submenu.addItem(.separator())
        self.addActionableSections(sections, to: submenu, width: width, provider: provider, captureMenu: submenu)
        while submenu.items.last?.isSeparatorItem == true {
            submenu.removeItem(at: submenu.items.count - 1)
        }
    }

    func makeOverviewRowSubmenu(
        provider: UsageProvider,
        model: UsageMenuCardView.Model,
        width: CGFloat) -> NSMenu?
    {
        if provider == .openai,
           self.settings.costSummaryShowsSubmenu(for: provider),
           let submenu = self.makeOpenAIAPIUsageSubmenu(provider: provider, width: width)
        {
            return submenu
        }
        // Mistral's top usage pane has no rate-limit bars of its own, so its Overview row prioritizes
        // cost history when the display style permits it. Other `tokenCostRequiresProviderSnapshot`
        // providers (e.g. opencodego) show real rate-limit bars and fall through to the generic check.
        if provider == .mistral,
           self.settings.costSummaryShowsSubmenu(for: provider),
           let submenu = self.makeCostHistorySubmenu(provider: provider, width: width)
        {
            return submenu
        }
        if self.settings.costSummaryShowsSubmenu(for: provider),
           model.tokenUsage != nil,
           let submenu = self.makeCostHistorySubmenu(provider: provider, width: width)
        {
            return submenu
        }
        return self.makeStorageBreakdownSubmenu(provider: provider, width: width)
    }
}

/// Detail submenu that appends its chart and actions the first time AppKit is about to show it.
/// It is its own delegate for that, so it forwards open and close to the controller, which tracks it
/// like a hosted chart submenu: a parent rebuild waits until it closes.
final class OverviewDetailMenu: NSMenu, NSMenuDelegate {
    private weak var controller: StatusItemController?
    private var appendContent: ((NSMenu) -> Void)?

    init(controller: StatusItemController, appendContent: @escaping (NSMenu) -> Void) {
        self.controller = controller
        self.appendContent = appendContent
        super.init(title: "")
        self.delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let appendContent = self.appendContent else { return }
        self.appendContent = nil
        appendContent(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        self.controller?.menuWillOpen(menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        self.controller?.menuDidClose(menu)
    }
}
