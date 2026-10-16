import AppKit
import SwiftUI

/// Card rows draw their own selection state. Keeping AppKit's parallel highlight hidden also
/// prevents newer menu implementations from painting a native selection behind the custom view.
final class MenuCardMenuItem: NSMenuItem {
    override var isHighlighted: Bool {
        false
    }
}

extension StatusItemController {
    func refreshMenuCardHeights(in menu: NSMenu) {
        let width = self.renderedMenuWidth(for: menu)
        for item in menu.items {
            if let view = item.view as? MenuFooterBarView {
                if abs(view.frame.width - width) > 0.5 { view.applyWidth(width) }
                continue
            }
            guard let view = item.view, let measuring = view as? any MenuCardMeasuring else { continue }
            guard abs(view.frame.width - width) > 0.5 else { continue }
            let id = item.representedObject as? String ?? "menuCard"
            let scope = self.menuProvider(for: menu)?.rawValue ?? id
            let height = self.cachedMenuCardHeight(for: id, scope: scope, width: width) {
                self.menuCardHeight(for: view, width: width)
            }
            measuring.applyMeasuredSize(width: width, height: height)
        }
    }

    func makeMenuCardItem(
        _ view: some View,
        id: String,
        width: CGFloat,
        heightCacheScope: String? = nil,
        heightCacheFingerprint: String? = nil,
        submenu: NSMenu? = nil,
        showsSubmenuIndicator: Bool = true,
        submenuIndicatorAlignment: Alignment = .topTrailing,
        submenuIndicatorTopPadding: CGFloat = 8,
        containsInteractiveControls: Bool = false,
        usesGPUSelection: Bool = false,
        tightVerticalFit: Bool = false,
        recyclesView: Bool = true,
        onClick: (() -> Void)? = nil) -> NSMenuItem
    {
        let allowsMenuHighlight = submenu != nil || onClick != nil
        if !self.menuCardRenderingEnabledForController {
            let item = NSMenuItem()
            item.title = ""
            item.isEnabled = allowsMenuHighlight
            item.representedObject = id
            item.submenu = submenu
            if submenu != nil {
                item.target = self
                item.action = #selector(self.menuCardNoOp(_:))
            }
            return item
        }

        // Content is erased so every row shares one outer AppKit class. Tab switches can replant
        // standard and GPU-selection payloads in place instead of detaching `item.view`.
        // Every hosted card row gets the action handler, so Overview and account layouts can open details too.
        let actionTarget = MenuCardActionTarget()
        let cardAction = ProviderCardAction(perform: { [weak self, actionTarget] action in
            guard let self else { return }
            actionTarget.item?.menu?.cancelTracking()
            let (selector, object) = self.selector(for: action)
            let sender = NSMenuItem()
            sender.representedObject = object
            NSApp.sendAction(selector, to: self, from: sender)
        })
        let payload = MenuCardRowPayload(
            content: AnyView(view
                .environment(\.providerMenuChartSettings, self.settings)
                .environment(\.providerCardAction, cardAction)),
            showsSubmenuIndicator: submenu != nil && showsSubmenuIndicator,
            submenuIndicatorAlignment: submenuIndicatorAlignment,
            submenuIndicatorTopPadding: submenuIndicatorTopPadding,
            allowsMenuHighlight: allowsMenuHighlight,
            containsInteractiveControls: containsInteractiveControls,
            usesGPUSelection: usesGPUSelection,
            tightVerticalFit: tightVerticalFit,
            onClick: onClick)
        let hosting: ErasedMenuCardHostingView
        if recyclesView,
           let recycled = self.takeRecyclableMenuCardView(
               for: id,
               as: ErasedMenuCardHostingView.self)
        {
            self.replantMenuCardRowPayload(payload, into: recycled)
            hosting = recycled
        } else {
            hosting = MenuRowContainerView(
                payload: payload,
                refreshMonitor: self.menuCardRefreshMonitor)
        }
        let height = self.cachedMenuCardHeight(
            for: id,
            scope: heightCacheScope ?? id,
            width: width,
            fingerprint: heightCacheFingerprint)
        {
            self.menuCardHeight(for: hosting, width: width)
        }
        hosting.applyMeasuredSize(width: width, height: height)
        let item = self.makeMenuCardNSMenuItem(
            hosting: hosting,
            id: id,
            submenu: submenu,
            isEnabled: allowsMenuHighlight || containsInteractiveControls)
        actionTarget.item = item
        return item
    }

    /// Wraps a measured hosting view in the `NSMenuItem` the menu installs, wiring submenu routing.
    private func makeMenuCardNSMenuItem(
        hosting: NSView,
        id: String,
        submenu: NSMenu?,
        isEnabled: Bool) -> NSMenuItem
    {
        let item = MenuCardMenuItem()
        // NSMenuItem()'s default title is the literal string "NSMenuItem"; Tahoe's
        // NSMenu paints that fallback title for frames where a row's view is
        // detached mid-mutation. Keep the fallback render blank instead.
        item.title = ""
        item.view = hosting
        item.isEnabled = isEnabled
        item.representedObject = id
        item.submenu = submenu
        if submenu != nil {
            item.target = self
            item.action = #selector(self.menuCardNoOp(_:))
        }
        return item
    }

    private func menuCardHeight(for view: NSView, width: CGFloat) -> CGFloat {
        // Tight-fit rows (Overview provider blocks) draw a continuous background across items, so the
        // standard air would read as a seam inside the block.
        let tight = (view as? MenuRowContainerView)?.rowPayload.tightVerticalFit ?? false
        let verticalPadding: CGFloat = tight ? 0 : 7 // 6pt of air plus 1pt of descender safety

        if let measured = view as? MenuCardMeasuring {
            return max(1, ceil(measured.measuredHeight(width: width) + verticalPadding))
        }

        view.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 1))
        let fitted = view.fittingSize
        return max(1, ceil(fitted.height + verticalPadding))
    }
}

/// Resolves the hosting menu when a card action fires, so tracking ends from whichever menu shows the row.
@MainActor
final class MenuCardActionTarget {
    weak var item: NSMenuItem?
}
