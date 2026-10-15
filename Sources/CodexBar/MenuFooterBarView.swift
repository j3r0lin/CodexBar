import AppKit

/// One icon button in the menu's bottom bar.
struct MenuFooterButton: Equatable {
    /// SF Symbol name.
    let systemImageName: String
    /// Shown as the tooltip; also the button's accessibility label.
    let label: String
    let action: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.systemImageName == rhs.systemImageName && lhs.label == rhs.label
    }
}

/// One row of borderless icon buttons that replaces the text rows at the bottom of the status menu.
/// The menu is pinned to darkAqua, so the idle tint is a light grey that stays readable on that background.
@MainActor
final class MenuFooterBarView: NSView {
    static let barHeight: CGFloat = 36
    private static let buttonSide: CGFloat = 28
    /// The buttons stay in a cluster in the middle of the bar rather than spreading across it.
    private static let buttonGap: CGFloat = 22
    private static let iconSide: CGFloat = 15
    private static let highlightCornerRadius: CGFloat = 6
    private static let idleTint = NSColor(white: 0.78, alpha: 1)

    private var buttons: [Button] = []

    /// True while the named symbol's button is showing its in-progress animation.
    func isSpinning(systemImageName: String) -> Bool {
        self.buttons.contains { $0.model.systemImageName == systemImageName && $0.isSpinning }
    }

    /// The layer that draws the named button's symbol, for checking where it turns.
    func iconLayer(systemImageName: String) -> CALayer? {
        self.buttons.first { $0.model.systemImageName == systemImageName }?.iconLayer
    }

    func button(labeled label: String) -> NSView? {
        self.buttons.first { $0.model.label == label }
    }

    /// Forces the hover highlight, so a render can show it without a pointer.
    func setHovering(_ hovering: Bool, labeled label: String) {
        self.buttons.first { $0.model.label == label }?.setHovering(hovering)
    }

    init(width: CGFloat, buttons: [MenuFooterButton]) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.barHeight))
        for button in buttons {
            let view = Button(model: button)
            self.addSubview(view)
            self.buttons.append(view)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyWidth(_ width: CGFloat) {
        self.frame.size.width = width
        self.needsLayout = true
    }

    /// Takes the other bar's button actions and labels while keeping this bar's views, so a menu rebuild
    /// leaves a spinning or hovered button as it is. Returns false when the buttons differ in kind.
    func adoptButtons(from other: MenuFooterBarView) -> Bool {
        guard self.buttons.map(\.model.systemImageName) == other.buttons.map(\.model.systemImageName)
        else { return false }
        for (button, replacement) in zip(self.buttons, other.buttons) {
            button.model = replacement.model
            button.toolTip = replacement.model.label
        }
        return true
    }

    /// Spins (or stops) the button whose symbol is `systemImageName`. Used for the refresh button.
    func setSpinning(_ spinning: Bool, systemImageName: String) {
        for button in self.buttons where button.model.systemImageName == systemImageName {
            button.setSpinning(spinning)
        }
    }

    override func layout() {
        super.layout()
        let count = CGFloat(self.buttons.count)
        guard count > 0 else { return }
        let cluster = count * Self.buttonSide + (count - 1) * Self.buttonGap
        let firstX = (self.bounds.width - cluster) / 2
        for (index, button) in self.buttons.enumerated() {
            button.frame = NSRect(
                x: floor(firstX + (Self.buttonSide + Self.buttonGap) * CGFloat(index)),
                y: floor((self.bounds.height - Self.buttonSide) / 2),
                width: Self.buttonSide,
                height: Self.buttonSide)
        }
    }

    private final class Button: NSView {
        var model: MenuFooterButton
        /// The symbol is drawn by a layer this view owns rather than by an NSImageView: AppKit resets
        /// the anchor point and position of a view's backing layer on layout, and a rotation about that
        /// reset anchor swings the icon around its corner instead of turning it in place.
        let iconLayer = CALayer()
        private let highlight = NSView()
        private var hovering = false
        private var tracking: NSTrackingArea?
        private(set) var isSpinning = false

        init(model: MenuFooterButton) {
            self.model = model
            super.init(frame: .zero)
            self.toolTip = model.label

            self.highlight.wantsLayer = true
            self.highlight.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
            self.highlight.layer?.cornerRadius = MenuFooterBarView.highlightCornerRadius
            self.highlight.isHidden = true
            self.addSubview(self.highlight)

            self.wantsLayer = true
            self.iconLayer.contents = Self.icon(named: model.systemImageName).map(Self.tinted)
            self.iconLayer.contentsGravity = .resizeAspect
            self.iconLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            self.iconLayer.zPosition = 1
            self.layer?.addSublayer(self.iconLayer)
        }

        private static func tinted(_ image: NSImage) -> NSImage {
            NSImage(size: image.size, flipped: false) { rect in
                image.draw(in: rect)
                MenuFooterBarView.idleTint.set()
                rect.fill(using: .sourceAtop)
                return true
            }
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            self.iconLayer.contentsScale = self.window?.backingScaleFactor ?? 2
        }

        /// One point size and one box for every symbol, so no button reads heavier than its neighbours.
        private static func icon(named name: String) -> NSImage? {
            guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
            let config = NSImage.SymbolConfiguration(pointSize: MenuFooterBarView.iconSide, weight: .medium)
            let configured = image.withSymbolConfiguration(config) ?? image
            configured.isTemplate = true
            return configured
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            self.highlight.frame = self.bounds
            let side = MenuFooterBarView.iconSide
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.iconLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            self.iconLayer.position = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
            CATransaction.commit()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking {
                self.removeTrackingArea(tracking)
            }
            let area = NSTrackingArea(
                rect: self.bounds,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                owner: self,
                userInfo: nil)
            self.addTrackingArea(area)
            self.tracking = area
        }

        override func mouseEntered(with event: NSEvent) {
            self.setHovering(true)
        }

        override func mouseExited(with event: NSEvent) {
            self.setHovering(false)
        }

        func setHovering(_ hovering: Bool) {
            self.hovering = hovering
            self.highlight.isHidden = !hovering
        }

        /// A view that takes the press is the one AppKit sends the matching release to.
        override func mouseDown(with event: NSEvent) {}

        override func mouseUp(with event: NSEvent) {
            guard self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return }
            self.model.action()
        }

        func setSpinning(_ spinning: Bool) {
            self.isSpinning = spinning
            if spinning {
                guard self.iconLayer.animation(forKey: "footerSpin") == nil else { return }
                let animation = CABasicAnimation(keyPath: "transform.rotation.z")
                animation.fromValue = 0
                animation.toValue = -Double.pi * 2
                animation.duration = 0.9
                animation.repeatCount = .infinity
                self.iconLayer.add(animation, forKey: "footerSpin")
            } else {
                self.iconLayer.removeAnimation(forKey: "footerSpin")
            }
        }

        override func isAccessibilityElement() -> Bool {
            true
        }

        override func accessibilityRole() -> NSAccessibility.Role? {
            .button
        }

        override func accessibilityLabel() -> String? {
            self.model.label
        }

        override func accessibilityPerformPress() -> Bool {
            self.model.action()
            return true
        }
    }
}
