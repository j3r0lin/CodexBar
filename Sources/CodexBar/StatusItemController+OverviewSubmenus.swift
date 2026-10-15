import AppKit
import CodexBarCore

extension StatusItemController {
    /// Hover submenu of an Overview row: the same usage detail the menu-bar ring card shows,
    /// followed by the provider's history chart when it has one.
    func makeOverviewDetailSubmenu(
        title: String,
        snapshot: UsageSnapshot?,
        provider: UsageProvider,
        model: UsageMenuCardView.Model,
        width: CGFloat) -> NSMenu
    {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.appearance = StatusMenuAppearance.menuAppearance
        submenu.addItem(self.makeMenuCardItem(
            AccountUsageDetailView(name: title, snapshot: snapshot, width: AccountUsageDetailView.defaultWidth),
            id: "overviewDetail-\(title)",
            width: AccountUsageDetailView.defaultWidth))
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

}
