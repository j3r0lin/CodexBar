import AppKit
import CodexBarCore

extension StatusItemController {
    /// Detail pages open under the account list, so each one starts with a row that returns to it.
    func addOverviewDetailHeader(title: String, width: CGFloat, to menu: NSMenu, captureMenu: NSMenu?) {
        let interactionMenu = captureMenu ?? menu
        let item = self.makeMenuCardItem(
            OverviewDetailHeaderRow(title: title, width: width),
            id: Self.overviewDetailBackIdentifier,
            width: width,
            heightCacheScope: "overviewDetailHeader",
            heightCacheFingerprint: title,
            usesGPUSelection: true,
            onClick: { [weak self, weak interactionMenu] in
                guard let self, let interactionMenu else { return }
                self.showOverviewHome(menu: interactionMenu)
            })
        item.target = self
        item.action = #selector(self.showOverviewHome(_:))
        menu.addItem(item)
        menu.addItem(.separator())
    }

    @objc func showOverviewHome(_ sender: NSMenuItem) {
        guard let menu = sender.menu else { return }
        self.showOverviewHome(menu: menu)
    }

    func showOverviewHome(menu: NSMenu) {
        guard !self.settings.mergedMenuLastSelectedWasOverview else { return }
        self.preservingMergedSwitcherContentCachesDuringInvalidation {
            self.settings.mergedMenuLastSelectedWasOverview = true
            self.lastMergedSwitcherSelection = .overview
            self.refreshProviderSelectionDependentUI(deferRendering: true)
        }
        self.clearMenuHighlight(ObjectIdentifier(menu))
        self.requestProviderSwitcherMenuRebuild(menu, provider: self.resolvedMenuProvider())
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
        if let submenu = self.makeUsageHistorySubmenu(provider: provider, width: width) {
            return submenu
        }
        return self.makeStorageBreakdownSubmenu(provider: provider, width: width)
    }

    @objc func selectOverviewProvider(_ sender: NSMenuItem) {
        guard let represented = sender.representedObject as? String,
              represented.hasPrefix(Self.overviewRowIdentifierPrefix)
        else {
            return
        }
        let parts = represented.dropFirst(Self.overviewRowIdentifierPrefix.count)
            .split(separator: "#", maxSplits: 1)
        let rawProvider = parts.first.map(String.init) ?? ""
        if parts.count == 2,
           let account = self.store.claudeAccountSource.accounts.first(where: { $0.id.opaqueID == parts[1] })
        {
            self.selectClaudeAccountTab(account.id)
        }
        guard let provider = UsageProvider(rawValue: rawProvider),
              let menu = sender.menu
        else {
            return
        }

        self.selectOverviewProvider(provider, menu: menu)
    }

    func selectOverviewProvider(_ provider: UsageProvider, menu: NSMenu) {
        if !self.settings.mergedMenuLastSelectedWasOverview, self.selectedMenuProvider == provider.instanceID { return }
        self.preservingMergedSwitcherContentCachesDuringInvalidation {
            self.settings.mergedMenuLastSelectedWasOverview = false
            self.lastMergedSwitcherSelection = .provider(provider.instanceID)
            self.selectedMenuProvider = provider.instanceID
            self.lastMenuProvider = provider.instanceID
            self.refreshProviderSelectionDependentUI(deferRendering: true)
        }
        // Custom-view clicks stay open and rebuild next turn. Standard menu-item activation can close;
        // menuWillOpen then renders the saved provider without doing structural work inside the action.
        self.clearMenuHighlight(ObjectIdentifier(menu))
        self.requestProviderSwitcherMenuRebuild(menu, provider: provider)
    }
}
