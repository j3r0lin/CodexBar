import AppKit

extension StatusItemController {
    /// A highlighted footer would keep the viewport restore after a manual refresh from running,
    /// so the footer drops its highlight while its refresh icon spins.
    private func clearFooterHighlightWhileRefreshing(in menu: NSMenu) {
        guard let highlighted = self.highlightedMenuItems[ObjectIdentifier(menu)],
              highlighted.view is MenuFooterBarView
        else { return }
        self.highlightedMenuItems.removeValue(forKey: ObjectIdentifier(menu))
    }

    /// Spins the refresh icon in every footer bar whose menu currently has a refresh in flight.
    func updateMenuFooterBars() {
        for bar in self.menuFooterBars.allObjects {
            guard let menu = bar.enclosingMenuItem?.menu else { continue }
            let spinning = self.isRefreshActionInFlight(for: menu)
            if spinning {
                self.clearFooterHighlightWhileRefreshing(in: menu)
            }
            bar.setSpinning(spinning, systemImageName: MenuDescriptor.MenuAction.refresh.systemImageName ?? "")
        }
    }

    func isRefreshActionInFlight(for menu: NSMenu) -> Bool {
        if self.store.hasForcedRefreshEnrichmentInFlight {
            return true
        }

        // An all-providers manual refresh (⌘R / overview) legitimately busies every row.
        if self.manualRefreshTasks[.global] != nil {
            return true
        }

        if self.isMergedOverviewSelected(in: menu) {
            // Overview stands for every provider, so it is busy while ANY manual refresh runs —
            // including the post-fetch tail of a per-provider refresh, after `refreshingProviders`
            // has cleared but its `.provider` task is still finishing status/token/credits work.
            return self.store.isRefreshing
                || !self.manualRefreshTasks.isEmpty
                || !self.store.refreshingProviders.isEmpty
        }
        if let provider = self.manualRefreshProvider(for: menu) {
            // A manual refresh of a different provider must not grey out this provider's row: only
            // reflect the global refresh, this provider's own manual refresh, and its store refresh.
            return self.store.isRefreshing
                || self.manualRefreshTasks[.provider(provider)] != nil
                || self.store.refreshingProviders.contains(provider)
        }
        return self.store.isRefreshing
            || !self.manualRefreshTasks.isEmpty
            || !self.store.refreshingProviders.isEmpty
    }

    func isMergedOverviewSelected(in menu: NSMenu) -> Bool {
        guard self.shouldMergeIcons else { return false }
        if let mergedMenu = self.mergedMenu, menu !== mergedMenu { return false }
        return true
    }
}
