import AppKit
import CodexBarCore
import SwiftUI

extension StatusItemController {
    /// Smart update: rebuild the menu content in place instead of replacing the whole menu.
    struct MenuUpdateContext {
        let provider: UsageProvider?
        let currentProvider: UsageProvider
        let switcherSelection: ProviderSwitcherSelection
        let menuWidth: CGFloat
        let codexAccountDisplay: CodexAccountMenuDisplay?
        let tokenAccountDisplay: TokenAccountMenuDisplay?
        let openAIContext: OpenAIWebContext
        let descriptor: MenuDescriptor
    }

    /// Rebuilds the merged menu in place: recycles the outgoing hosting views and reconciles
    /// rows whose shape is unchanged, so an open tracked menu sees content mutations instead
    /// of item churn. The fresh content is built into a detached scratch menu while its
    /// interaction closures capture the live menu they will serve.
    func updateMergedMenuContentInPlace(
        _ menu: NSMenu,
        context: MenuUpdateContext)
    {
        self.performMenuMutationWithoutAnimation {
            defer { self.flushHostedMenuRowRendering(in: menu) }
            let shapes = self.menuContentShapes(in: menu, fromIndex: 0)
            self.harvestRecyclableMenuCardViews(in: menu, fromIndex: 0, preserveHighlightedItem: true)
            defer { self.clearMenuCardViewRecyclePool() }
            self.rememberMergedMenuState()
            let scratch = NSMenu()
            scratch.autoenablesItems = false
            self.addMenuContent(into: scratch, captureMenu: menu, context: context)
            self.reconcileMenuContent(menu, fromIndex: 0, shapes: shapes, with: scratch)
            self.refreshMenuCardHeights(in: menu)
        }
    }

    /// Adds the menu content (account switchers, card content, and actionable sections)
    /// to `target`, which may be a detached scratch menu; interaction
    /// closures always capture `captureMenu`, the live menu the rows will serve.
    func addMenuContent(
        into target: NSMenu,
        captureMenu: NSMenu,
        context: MenuUpdateContext)
    {
        self.addCodexAccountSwitcherIfNeeded(
            to: target,
            display: context.codexAccountDisplay,
            width: context.menuWidth,
            captureMenu: captureMenu)
        self.lastCodexAccountMenuDisplay = context.codexAccountDisplay
        self.addTokenAccountSwitcherIfNeeded(
            to: target,
            display: context.tokenAccountDisplay,
            width: context.menuWidth,
            captureMenu: captureMenu)
        self.lastTokenAccountMenuDisplay = context.tokenAccountDisplay

        let menuContext = MenuCardContext(
            currentProvider: context.currentProvider,
            selectedProvider: context.provider,
            menuWidth: context.menuWidth,
            codexAccountDisplay: context.codexAccountDisplay,
            tokenAccountDisplay: context.tokenAccountDisplay,
            openAIContext: context.openAIContext)
        self.addPrimaryMenuContent(
            to: target,
            context: menuContext,
            switcherSelection: context.switcherSelection,
            captureMenu: captureMenu)
        let overviewChrome = context.switcherSelection == .overview
        self.addActionableSections(
            context.descriptor.sections,
            to: target,
            width: context.menuWidth,
            provider: context.currentProvider,
            captureMenu: captureMenu,
            footerBarActions: overviewChrome ? [.about, .quit] : nil)
        self.appendOverviewFooterStatusIfNeeded(
            to: target,
            switcherSelection: overviewChrome ? .overview : nil,
            width: context.menuWidth)
    }
}
