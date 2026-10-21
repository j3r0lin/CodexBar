import AppKit
import CodexBarCore
import Observation
import SwiftUI

extension StatusItemController {
    func applySubtitle(_ subtitle: String, to item: NSMenuItem, title: String) {
        if #available(macOS 14.4, *) {
            // NSMenuItem.subtitle is only available on macOS 14.4+.
            item.subtitle = subtitle
        } else {
            item.view = self.makeMenuSubtitleView(title: title, subtitle: subtitle, isEnabled: item.isEnabled)
            item.toolTip = "\(title) — \(subtitle)"
        }
    }

    func makeMenuSubtitleView(title: String, subtitle: String, isEnabled: Bool) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.alphaValue = isEnabled ? 1.0 : 0.7

        let titleField = NSTextField(labelWithString: title)
        titleField.font = NSFont.menuFont(ofSize: NSFont.systemFontSize)
        titleField.textColor = NSColor.labelColor
        titleField.lineBreakMode = .byTruncatingTail
        titleField.maximumNumberOfLines = 1
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let subtitleField = NSTextField(labelWithString: subtitle)
        subtitleField.font = NSFont.menuFont(ofSize: NSFont.smallSystemFontSize)
        subtitleField.textColor = NSColor.secondaryLabelColor
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.maximumNumberOfLines = 1
        subtitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [titleField, subtitleField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -2),
        ])

        return container
    }
}

@MainActor
protocol MenuCardHighlighting: AnyObject {
    var allowsMenuHighlight: Bool { get }
    func setHighlighted(_ highlighted: Bool)
}

extension MenuCardHighlighting {
    var allowsMenuHighlight: Bool {
        true
    }
}

@MainActor
protocol MenuCardMeasuring: AnyObject {
    func measuredHeight(width: CGFloat) -> CGFloat
    func applyMeasuredSize(width: CGFloat, height: CGFloat)
}

@MainActor
@Observable
final class MenuCardHighlightState {
    var isHighlighted = false
}

final class MenuHostingView<Content: View>: NSHostingView<Content> {
    /// The height AppKit should give this item's menu row. NSMenu reads `intrinsicContentSize`
    /// (not the explicit `frame`) when it lays out custom-view rows, so a measured height that
    /// only lives in `frame` is silently reverted to the open-time row height — leaving the
    /// SwiftUI content centered in a stale, oversized row. Routing the height through the
    /// intrinsic size is the channel the menu actually honors.
    private var measuredHeight: CGFloat?

    override var allowsVibrancy: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        guard let measuredHeight else { return super.intrinsicContentSize }
        return NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight)
    }

    func applyMeasuredHeight(width: CGFloat, height: CGFloat) {
        let resolvedHeight = max(1, ceil(height))
        guard self.measuredHeight != resolvedHeight || self.frame.height != resolvedHeight else { return }

        self.measuredHeight = resolvedHeight
        self.frame = NSRect(
            origin: self.frame.origin,
            size: NSSize(width: width, height: resolvedHeight))
        self.invalidateIntrinsicContentSize()
        self.layoutSubtreeIfNeeded()
        self.superview?.layoutSubtreeIfNeeded()
    }

    /// Measures the true SwiftUI content height at `width`. The cached `measuredHeight` is routed
    /// through `intrinsicContentSize`, so `fittingSize` would otherwise echo the stale cached value;
    /// clearing it for the measurement lets the live content size drive the result. Used to resize
    /// the row exactly when expandable content (e.g. status groups) toggles.
    func measuredFittingHeight(width: CGFloat) -> CGFloat {
        let saved = self.measuredHeight
        self.measuredHeight = nil
        self.frame = NSRect(origin: self.frame.origin, size: NSSize(width: width, height: 1))
        self.invalidateIntrinsicContentSize()
        self.layoutSubtreeIfNeeded()
        let height = self.fittingSize.height
        self.measuredHeight = saved
        return height
    }
}

/// Row payload remembered by erased hosting views so tab switches can exchange
/// SwiftUI content between an attached and a cached hosting view without ever
/// detaching `item.view`. Detaching mid-tracking makes Tahoe's NSMenu paint the
/// row's fallback title ("NSMenuItem") for a few frames — the tab-switch flash.
@MainActor
struct MenuCardRowPayload {
    let content: AnyView
    let showsSubmenuIndicator: Bool
    let submenuIndicatorAlignment: Alignment
    let submenuIndicatorTopPadding: CGFloat
    let allowsMenuHighlight: Bool
    let containsInteractiveControls: Bool
    let usesGPUSelection: Bool
    /// Rows that draw a continuous background across neighbouring items (Overview provider blocks)
    /// opt out of the standard vertical air so the panels meet without a seam.
    var tightVerticalFit: Bool = false
    /// When the row is part of an Overview block, this keeps the hover highlight on that row's
    /// piece of the block instead of the whole menu item.
    var selectionBlock: OverviewBlockPosition?
    let onClick: (() -> Void)?
}

/// One stable AppKit class for every menu-card row. Keeping the outer view attached while payloads
/// move between Overview and provider rows prevents Tahoe from painting NSMenuItem's fallback title.
@MainActor
final class MenuRowContainerView: NSView, MenuCardHighlighting, MenuCardMeasuring {
    let highlightState: MenuCardHighlightState
    let interactiveRegionStore: MenuCardInteractiveRegionStore
    private let hosting: NSHostingView<MenuCardSectionContainerView<AnyView>>
    private var measuredSize: NSSize?
    private var selectionView: NSView?
    private var blockBaseView: NSView?
    private(set) var allowsMenuHighlight: Bool
    private var onClick: (() -> Void)?
    private var containsInteractiveControls: Bool
    private var isRowHighlighted = false
    private var isPressed = false
    private var isForwardingHostedControlPress = false
    private(set) var rowPayload: MenuCardRowPayload
    #if DEBUG
    private var testForwardedHostedControlMouseDown = false
    private var testForwardedHostedControlMouseUp = false
    #endif

    private static let selectionHorizontalInset: CGFloat = 6
    private static let selectionVerticalInset: CGFloat = 2
    private static let selectionCornerRadius: CGFloat = 6
    private static let selectionFadeDuration: CFTimeInterval = 0.06

    override var intrinsicContentSize: NSSize {
        let width = self.frame.width > 0 ? self.frame.width : NSView.noIntrinsicMetric
        return NSSize(width: width, height: self.measuredSize?.height ?? self.hosting.intrinsicContentSize.height)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != self.frame.width
        if widthChanged {
            self.measuredSize = nil
        }
        super.setFrameSize(newSize)
        if widthChanged {
            self.invalidateIntrinsicContentSize()
        }
    }

    /// NSMenu uses intrinsic height even when a cached row has an explicit frame. Publish the
    /// measurement here so a detached SwiftUI host cannot shrink the row on its first attachment.
    func applyMeasuredSize(width: CGFloat, height: CGFloat) {
        let size = NSSize(width: width, height: max(1, ceil(height)))
        self.setFrameSize(size)
        self.measuredSize = size
        self.invalidateIntrinsicContentSize()
        self.needsLayout = true
    }

    init(
        payload: MenuCardRowPayload,
        refreshMonitor: MenuCardRefreshMonitor?)
    {
        let highlightState = MenuCardHighlightState()
        let interactiveRegionStore = MenuCardInteractiveRegionStore()
        self.highlightState = highlightState
        self.interactiveRegionStore = interactiveRegionStore
        self.rowPayload = payload
        self.allowsMenuHighlight = payload.allowsMenuHighlight
        self.containsInteractiveControls = payload.containsInteractiveControls
        self.onClick = payload.onClick
        self.hosting = NSHostingView(rootView: Self.makeRootView(
            payload: payload,
            highlightState: highlightState,
            refreshMonitor: refreshMonitor,
            interactiveRegionStore: interactiveRegionStore))
        super.init(frame: .zero)
        self.wantsLayer = true
        self.hosting.wantsLayer = true
        self.hosting.autoresizingMask = [.width, .height]
        self.addSubview(self.hosting)
        self.configureSelectionMode(animated: false)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Rebuilds the erased SwiftUI root around this container's own state and interaction store.
    /// The outer NSView never detaches, even when switching between GPU and SwiftUI highlight modes.
    func replant(_ payload: MenuCardRowPayload, refreshMonitor: MenuCardRefreshMonitor?) {
        self.measuredSize = nil
        self.rowPayload = payload
        self.allowsMenuHighlight = payload.allowsMenuHighlight
        self.containsInteractiveControls = payload.containsInteractiveControls
        self.onClick = payload.onClick
        self.isPressed = false
        self.isForwardingHostedControlPress = false
        self.highlightState.isHighlighted = !payload.usesGPUSelection && self.isRowHighlighted
        self.hosting.rootView = Self.makeRootView(
            payload: payload,
            highlightState: self.highlightState,
            refreshMonitor: refreshMonitor,
            interactiveRegionStore: self.interactiveRegionStore)
        self.configureSelectionMode(animated: false)
        self.updateSelectionShape()
        self.invalidateIntrinsicContentSize()
    }

    /// `NSMenu` tracking consumes keyboard events before they reach a menu item's custom view, so
    /// the pointer `onClick` path has no native counterpart for assistive tech. Expose the row as an
    /// accessibility button whose press mirrors a click, giving VoiceOver an activation path that runs
    /// `onClick` (and therefore keeps the menu open) instead of regressing to mouse-only.
    override func accessibilityRole() -> NSAccessibility.Role? {
        self.onClick == nil ? super.accessibilityRole() : .button
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onClick = self.onClick else {
            return super.accessibilityPerformPress()
        }
        onClick()
        return true
    }

    override func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()
        self.hosting.frame = self.bounds
        let selectionFrame = Self.selectionFrame(in: self.bounds, block: self.rowPayload.selectionBlock)
        self.selectionView?.frame = selectionFrame
        self.blockBaseView?.frame = selectionFrame
        self.updateSelectionShape()
    }

    /// Overview rows highlight exactly their piece of the provider block; other rows keep the
    /// standard inset selection frame.
    static func selectionFrame(in bounds: NSRect, block: OverviewBlockPosition?) -> NSRect {
        guard let block else {
            return bounds.insetBy(dx: self.selectionHorizontalInset, dy: self.selectionVerticalInset)
        }
        // The gap below a provider card stays outside the highlight.
        let height = bounds.height - (block.roundsBottom ? OverviewCompactAccountRow.blockGap : 0)
        return NSRect(
            x: OverviewCompactAccountRow.blockInset,
            y: bounds.height - height,
            width: bounds.width - 2 * OverviewCompactAccountRow.blockInset,
            height: height)
    }

    private static func selectionMaskCorners(for block: OverviewBlockPosition) -> CACornerMask {
        switch block {
        case .single:
            [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .top:
            [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        case .middle:
            []
        case .bottom:
            [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let descendant = super.hitTest(point)
        if let descendant {
            var current: NSView? = descendant
            while let view = current, view !== self {
                if view is NSButton || view is NSControl {
                    return descendant
                }
                current = view.superview
            }
            if self.hitsHostedInteractiveControl(at: point) {
                return descendant
            }
            if descendant !== self, self.onClick != nil {
                return self
            }
        }
        return descendant
    }

    private func locationInView(for event: NSEvent) -> NSPoint {
        guard self.window != nil else {
            return event.locationInWindow
        }
        return self.convert(event.locationInWindow, from: nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.type == .leftMouseDown, self.onClick != nil else {
            super.mouseDown(with: event)
            return
        }
        let localPoint = self.locationInView(for: event)
        if self.beginPrimaryPress(at: localPoint) {
            #if DEBUG
            self.testForwardedHostedControlMouseDown = true
            #endif
            super.mouseDown(with: event)
            return
        }
        guard self.rowPayload.usesGPUSelection else { return }
        guard self.bounds.contains(localPoint), let window = self.window else {
            self.isPressed = false
            return
        }

        // A submenu-backed NSMenuItem consumes mouseUp in its nested tracking loop before a custom
        // view receives it. Track the drag/up sequence directly in GPU mode so release-inside
        // cancellation remains native and the row action runs before the menu can close.
        var shouldInvoke = false
        window.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking)
        { [weak self] trackedEvent, stop in
            guard let self, let trackedEvent else {
                stop.pointee = true
                return
            }
            if self.primaryPressShouldYieldToMenu(for: trackedEvent) {
                window.postEvent(trackedEvent, atStart: true)
                stop.pointee = true
                return
            }
            guard let decision = self.primaryPressDecision(for: trackedEvent) else { return }
            shouldInvoke = decision
            stop.pointee = true
        }
        self.isPressed = false
        if shouldInvoke {
            self.onClick?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard event.type == .leftMouseUp, self.onClick != nil else {
            super.mouseUp(with: event)
            return
        }
        let result = self.endPrimaryPress(at: self.locationInView(for: event))
        if result.forwardToHostedControl {
            #if DEBUG
            self.testForwardedHostedControlMouseUp = true
            #endif
            super.mouseUp(with: event)
            return
        }
        if result.invokeRowAction {
            self.onClick?()
        }
    }

    /// Returns whether AppKit should forward the press into a nested SwiftUI control.
    private func beginPrimaryPress(at point: NSPoint) -> Bool {
        if self.hitsHostedInteractiveControl(at: point) {
            self.isForwardingHostedControlPress = true
            return true
        }
        self.isPressed = self.bounds.contains(point)
        return false
    }

    private func endPrimaryPress(at point: NSPoint) -> (forwardToHostedControl: Bool, invokeRowAction: Bool) {
        if self.isForwardingHostedControlPress {
            self.isForwardingHostedControlPress = false
            return (true, false)
        }
        defer { self.isPressed = false }
        return (false, self.isPressed && self.bounds.contains(point))
    }

    private func hitsHostedInteractiveControl(at point: NSPoint) -> Bool {
        guard self.containsInteractiveControls else { return false }
        let hostedPoint = self.hosting.convert(point, from: self)
        return self.interactiveRegionStore.contains(
            hostedPoint,
            hostingBounds: self.hosting.bounds,
            fittedSize: self.hosting.fittingSize)
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        self.hosting.frame = NSRect(origin: self.hosting.frame.origin, size: NSSize(width: width, height: 1))
        self.hosting.layoutSubtreeIfNeeded()
        return self.hosting.fittingSize.height
    }

    func setHighlighted(_ highlighted: Bool) {
        guard self.isRowHighlighted != highlighted else { return }
        self.isRowHighlighted = highlighted
        self.applyHighlight(animated: true)
    }

    private func configureSelectionMode(animated: Bool) {
        if self.rowPayload.selectionBlock != nil {
            if self.blockBaseView == nil {
                // The base lives in AppKit, not in the SwiftUI card, so the selection layer between them
                // still brightens the card on hover; the menu material behind would otherwise tint it.
                let base = NSView()
                base.wantsLayer = true
                base.layer?.backgroundColor = NSColor(
                    srgbRed: 0.14, green: 0.14, blue: 0.16, alpha: 0.9).cgColor
                base.layer?.masksToBounds = true
                base.autoresizingMask = [.width, .height]
                self.addSubview(base, positioned: .below, relativeTo: self.selectionView ?? self.hosting)
                self.blockBaseView = base
            }
        } else {
            self.blockBaseView?.removeFromSuperview()
            self.blockBaseView = nil
        }
        if self.rowPayload.usesGPUSelection {
            _ = self.ensureSelectionView()
            self.updateSelectionShape()
        } else {
            self.selectionView?.removeFromSuperview()
            self.selectionView = nil
        }
        self.applyHighlight(animated: animated)
        self.needsLayout = true
    }

    private func applyHighlight(animated: Bool) {
        guard self.rowPayload.usesGPUSelection else {
            self.highlightState.isHighlighted = self.isRowHighlighted
            return
        }

        // The selection is drawn behind the row and the row keeps its own colours, so a usage bar
        // stays readable on it. The SwiftUI highlight state stays false so hovering never
        // re-invalidates the hosted graph.
        self.highlightState.isHighlighted = false
        let selectionView = self.ensureSelectionView()
        selectionView.frame = Self.selectionFrame(in: self.bounds, block: self.rowPayload.selectionBlock)
        let layer = selectionView.layer
        let targetOpacity: Float = self.isRowHighlighted ? 1 : 0
        if animated {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = layer?.presentation()?.opacity ?? (self.isRowHighlighted ? 0 : 1)
            fade.toValue = targetOpacity
            fade.duration = Self.selectionFadeDuration
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer?.add(fade, forKey: "selectionFade")
        }
        layer?.opacity = targetOpacity
    }

    private func ensureSelectionView() -> NSView {
        if let selectionView {
            return selectionView
        }
        // A brightened overlay keeps the block's colour language readable; the system selection
        // material would hide the severity colours it is meant to complement.
        let selectionView: NSView
        if self.rowPayload.selectionBlock != nil {
            selectionView = NSView()
            selectionView.wantsLayer = true
            selectionView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        } else {
            let material = NSVisualEffectView()
            material.material = .selection
            material.blendingMode = .withinWindow
            material.state = .active
            material.isEmphasized = true
            material.wantsLayer = true
            selectionView = material
        }
        selectionView.layer?.masksToBounds = true
        selectionView.layer?.opacity = 0
        selectionView.autoresizingMask = [.width, .height]
        self.addSubview(selectionView, positioned: .below, relativeTo: self.hosting)
        self.selectionView = selectionView
        self.updateSelectionShape()
        return selectionView
    }

    private func updateSelectionShape() {
        for layer in [self.selectionView?.layer, self.blockBaseView?.layer].compactMap(\.self) {
            if let block = self.rowPayload.selectionBlock {
                layer.maskedCorners = Self.selectionMaskCorners(for: block)
                layer.cornerRadius = block == .middle ? 0 : 10
            } else {
                layer.maskedCorners = [
                    .layerMinXMinYCorner, .layerMaxXMinYCorner,
                    .layerMinXMaxYCorner, .layerMaxXMaxYCorner,
                ]
                layer.cornerRadius = Self.selectionCornerRadius
            }
        }
    }

    private static func makeRootView(
        payload: MenuCardRowPayload,
        highlightState: MenuCardHighlightState,
        refreshMonitor: MenuCardRefreshMonitor?,
        interactiveRegionStore: MenuCardInteractiveRegionStore) -> MenuCardSectionContainerView<AnyView>
    {
        MenuCardSectionContainerView(
            highlightState: highlightState,
            showsSubmenuIndicator: payload.showsSubmenuIndicator,
            submenuIndicatorAlignment: payload.submenuIndicatorAlignment,
            submenuIndicatorTopPadding: payload.submenuIndicatorTopPadding,
            refreshMonitor: refreshMonitor,
            interactiveRegionStore: interactiveRegionStore,
            selectionBlock: payload.selectionBlock)
        {
            payload.content
        }
    }

    private func primaryPressDecision(for event: NSEvent) -> Bool? {
        guard event.type == .leftMouseUp else { return nil }
        return self.bounds.contains(self.locationInView(for: event))
    }

    private func primaryPressShouldYieldToMenu(for event: NSEvent) -> Bool {
        event.type == .leftMouseDragged && !self.bounds.contains(self.locationInView(for: event))
    }
}

typealias ErasedMenuCardHostingView = MenuRowContainerView

#if DEBUG
extension MenuRowContainerView {
    var _test_forwardedHostedControlEvents: (mouseDown: Bool, mouseUp: Bool) {
        (self.testForwardedHostedControlMouseDown, self.testForwardedHostedControlMouseUp)
    }

    func _test_hitsHostedInteractiveControl(at point: NSPoint) -> Bool {
        self.hitsHostedInteractiveControl(at: point)
    }

    func _test_simulateRuntimeClick(at point: NSPoint? = nil) -> Bool {
        let clickPoint = point ?? NSPoint(x: self.bounds.midX, y: self.bounds.midY)
        guard let onClick = self.onClick else { return false }
        if self.rowPayload.usesGPUSelection {
            guard self.hitTest(clickPoint) === self, self.bounds.contains(clickPoint) else { return false }
            onClick()
            return true
        }
        guard !self.beginPrimaryPress(at: clickPoint) else {
            _ = self.endPrimaryPress(at: clickPoint)
            return false
        }
        let result = self.endPrimaryPress(at: clickPoint)
        guard result.invokeRowAction else { return false }
        onClick()
        return true
    }

    func _test_primaryPressDecision(for event: NSEvent) -> Bool? {
        self.primaryPressDecision(for: event)
    }

    func _test_primaryPressShouldYieldToMenu(for event: NSEvent) -> Bool {
        self.primaryPressShouldYieldToMenu(for: event)
    }

    var isHighlightedForTesting: Bool {
        self.isRowHighlighted
    }

    var swiftUIHighlightStateIsHighlightedForTesting: Bool {
        self.highlightState.isHighlighted
    }

    var usesGPUSelectionForTesting: Bool {
        self.rowPayload.usesGPUSelection
    }

    var hasGPUSelectionLayerForTesting: Bool {
        self.selectionView != nil
    }
}
#endif

struct MenuCardSectionContainerView<Content: View>: View {
    @Bindable var highlightState: MenuCardHighlightState
    let showsSubmenuIndicator: Bool
    let submenuIndicatorAlignment: Alignment
    let submenuIndicatorTopPadding: CGFloat
    var refreshMonitor: MenuCardRefreshMonitor?
    var interactiveRegionStore: MenuCardInteractiveRegionStore?
    var selectionBlock: OverviewBlockPosition?
    @ViewBuilder let content: () -> Content

    init(
        highlightState: MenuCardHighlightState,
        showsSubmenuIndicator: Bool,
        submenuIndicatorAlignment: Alignment,
        submenuIndicatorTopPadding: CGFloat,
        refreshMonitor: MenuCardRefreshMonitor?,
        interactiveRegionStore: MenuCardInteractiveRegionStore? = nil,
        selectionBlock: OverviewBlockPosition? = nil,
        @ViewBuilder content: @escaping () -> Content)
    {
        self.highlightState = highlightState
        self.showsSubmenuIndicator = showsSubmenuIndicator
        self.submenuIndicatorAlignment = submenuIndicatorAlignment
        self.submenuIndicatorTopPadding = submenuIndicatorTopPadding
        self.refreshMonitor = refreshMonitor
        self.interactiveRegionStore = interactiveRegionStore
        self.selectionBlock = selectionBlock
        self.content = content
    }

    var body: some View {
        self.content()
            .environment(\.menuItemHighlighted, self.highlightState.isHighlighted)
            .environment(\.menuCardRefreshMonitor, self.refreshMonitor)
            .coordinateSpace(name: MenuCardInteractiveRegionPreferenceKey.coordinateSpaceName)
            .onPreferenceChange(MenuCardInteractiveRegionPreferenceKey.self) { regions in
                self.interactiveRegionStore?.regions = regions
            }
            .foregroundStyle(MenuHighlightStyle.primary(self.highlightState.isHighlighted))
            .background(alignment: .topLeading) {
                if self.highlightState.isHighlighted {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(MenuHighlightStyle.selectionBackground(true))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                }
            }
            .overlay(alignment: self.submenuIndicatorAlignment) {
                if self.showsSubmenuIndicator {
                    Image(systemName: "chevron.forward")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(MenuHighlightStyle.secondary(self.highlightState.isHighlighted))
                        .padding(.top, self.submenuIndicatorTopPadding)
                        .padding(.trailing, 10)
                }
            }
            .codexBarLocalized()
    }
}

@MainActor
@Observable
final class MenuCardInteractiveRegionStore {
    var regions: [CGRect] = []

    func contains(_ point: CGPoint, hostingBounds: CGRect, fittedSize: CGSize) -> Bool {
        // NSHostingView centers intrinsic-height SwiftUI content in the menu item's padded frame.
        // Preference rectangles use the SwiftUI root's coordinates, so remove that AppKit offset.
        let contentOrigin = CGPoint(
            x: max(0, (hostingBounds.width - fittedSize.width) / 2),
            y: max(0, (hostingBounds.height - fittedSize.height) / 2))
        let contentPoint = CGPoint(x: point.x - contentOrigin.x, y: point.y - contentOrigin.y)
        return self.regions.contains { $0.contains(contentPoint) }
    }
}

struct MenuCardInteractiveRegionPreferenceKey: PreferenceKey {
    static let coordinateSpaceName = "MenuCardInteractiveRegion"
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

extension View {
    func menuCardInteractiveControl(isEnabled: Bool = true) -> some View {
        self.background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: MenuCardInteractiveRegionPreferenceKey.self,
                    value: isEnabled
                        ? [proxy.frame(in: .named(MenuCardInteractiveRegionPreferenceKey.coordinateSpaceName))]
                        : [])
            }
        }
    }
}
