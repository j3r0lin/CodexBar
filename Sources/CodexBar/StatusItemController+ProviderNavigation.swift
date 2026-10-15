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
}
