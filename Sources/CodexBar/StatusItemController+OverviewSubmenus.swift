import AppKit
import CodexBarCore

extension StatusItemController {
    /// Hover submenu of an Overview row: the account's usage detail, followed by the provider's
    /// history chart when it has one. A magpie Claude row also refreshes that one account.
    func makeOverviewDetailSubmenu(
        title: String,
        snapshot: UsageSnapshot?,
        provider: UsageProvider,
        model: UsageMenuCardView.Model,
        width: CGFloat,
        claudeAccountID: ProviderAccountIdentity? = nil) -> NSMenu
    {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.appearance = StatusMenuAppearance.menuAppearance
        submenu.addItem(self.makeMenuCardItem(
            AccountUsageDetailView(name: title, snapshot: snapshot, width: AccountUsageDetailView.defaultWidth),
            id: "overviewDetail-\(title)",
            width: AccountUsageDetailView.defaultWidth))
        if let claudeAccountID {
            submenu.addItem(.separator())
            submenu.addItem(self.makeRefreshClaudeAccountItem(claudeAccountID))
        }
        if let chartMenu = self.makeOverviewRowSubmenu(provider: provider, model: model, width: width) {
            submenu.addItem(.separator())
            let chartItem = NSMenuItem(title: L("Usage history (30 days)"), action: nil, keyEquivalent: "")
            chartItem.submenu = chartMenu
            submenu.addItem(chartItem)
        }
        return submenu
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
        self.requestProviderSwitcherMenuRebuild(menu, provider: provider)
    }
}
