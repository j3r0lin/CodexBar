import AppKit
import CodexBarCore

extension StatusItemController {
    /// Hover submenu of an Overview row: the shared usage detail, followed inline by the provider's
    /// history chart when it has data. The chart is built on first open so unopened rows stay cheap.
    func makeOverviewDetailSubmenu(
        title: String,
        snapshot: UsageSnapshot?,
        provider: UsageProvider,
        model: UsageMenuCardView.Model,
        width: CGFloat) -> NSMenu
    {
        let submenu = OverviewDetailMenu { [weak self] submenu in
            guard let self,
                  let chartMenu = self.makeOverviewRowSubmenu(provider: provider, model: model, width: width)
            else { return }
            self.hydrateHostedSubviewMenuIfNeeded(chartMenu, width: width)
            let chartItems = chartMenu.items
            // An empty history hydrates to a disabled "No data available" row; show no chart at all then.
            guard chartItems.contains(where: \.isEnabled) else { return }
            chartMenu.removeAllItems()
            submenu.addItem(.separator())
            chartItems.forEach(submenu.addItem)
        }
        submenu.autoenablesItems = false
        submenu.minimumWidth = width
        submenu.appearance = StatusMenuAppearance.menuAppearance
        submenu.addItem(self.makeMenuCardItem(
            AccountUsageDetailView(name: title, snapshot: snapshot, width: width),
            id: "overviewDetail-\(title)",
            width: width))
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

/// Detail submenu that appends its chart the first time AppKit is about to show it.
final class OverviewDetailMenu: NSMenu, NSMenuDelegate {
    private var appendChart: ((NSMenu) -> Void)?

    init(appendChart: @escaping (NSMenu) -> Void) {
        self.appendChart = appendChart
        super.init(title: "")
        self.delegate = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let appendChart = self.appendChart else { return }
        self.appendChart = nil
        appendChart(menu)
    }
}
