import AppKit
import CodexBarCore

extension StatusItemController {
    func refreshProviderSelectionDependentUI(
        refreshOpenMenus: Bool = false,
        deferRendering: Bool = false)
    {
        #if DEBUG
        guard !self.isReleasedForTesting else { return }
        #endif
        self.advanceMenuInteraction(for: self.mergedMenu)
        self.invalidateMenus(refreshOpenMenus: refreshOpenMenus)
        if deferRendering {
            self.scheduleProviderSelectionUIRefresh()
            return
        }
        self.refreshProviderSelectionRendering()
    }

    private func scheduleProviderSelectionUIRefresh() {
        self.providerSelectionUIRefreshTask?.cancel()
        self.providerSelectionUIRefreshTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            self.refreshProviderSelectionRendering()
            self.providerSelectionUIRefreshTask = nil
        }
    }

    private func refreshProviderSelectionRendering() {
        self.updateAnimationState()
        self.updateBlinkingState()
        let phase: Double? = self.activeLoadingAnimationPhase()
        self.applyIcon(phase: phase)
    }

    func navigateProviderSwitcher(
        _ direction: StatusItemMenuProviderNavigationDirection,
        menu: NSMenu? = nil)
    {
        guard self.shouldMergeIcons else { return }
        let visibleMenu = menu ?? self.providerSwitcherShortcutMenuID.flatMap { self.openMenus[$0] }
        // Right opens the highlighted account; left (and Escape, routed here) returns to the list.
        if direction == .next {
            if let visibleMenu, let item = self.highlightedMenuItems[ObjectIdentifier(visibleMenu)],
               item.action != nil
            {
                _ = NSApp.sendAction(item.action!, to: item.target, from: item)
            }
            return
        }
        if let visibleMenu {
            self.showOverviewHome(menu: visibleMenu)
        }
    }
}
