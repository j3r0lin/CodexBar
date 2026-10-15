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
    private static let iconSide: CGFloat = 15
    private static let highlightCornerRadius: CGFloat = 6
    private static let idleTint = NSColor(white: 0.78, alpha: 1)

    private var buttons: [Button] = []

    /// True while the named symbol's button is showing its in-progress animation.
    func isSpinning(systemImageName: String) -> Bool {
        self.buttons.contains { $0.model.systemImageName == systemImageName && $0.isSpinning }
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
        let slot = self.bounds.width / count
        for (index, button) in self.buttons.enumerated() {
            button.frame = NSRect(
                x: floor(slot * CGFloat(index) + (slot - Self.buttonSide) / 2),
                y: floor((self.bounds.height - Self.buttonSide) / 2),
                width: Self.buttonSide,
                height: Self.buttonSide)
        }
    }

    private final class Button: NSView {
        let model: MenuFooterButton
        private let iconView = NSImageView()
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

            if let image = NSImage(systemSymbolName: model.systemImageName, accessibilityDescription: nil) {
                image.isTemplate = true
                self.iconView.image = image
                self.iconView.contentTintColor = MenuFooterBarView.idleTint
                self.iconView.imageScaling = .scaleProportionallyDown
                let config = NSImage.SymbolConfiguration(pointSize: MenuFooterBarView.iconSide, weight: .medium)
                self.iconView.symbolConfiguration = config
            }
            self.addSubview(self.iconView)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            self.highlight.frame = self.bounds
            let side = MenuFooterBarView.iconSide
            self.iconView.frame = NSRect(
                x: floor((self.bounds.width - side) / 2),
                y: floor((self.bounds.height - side) / 2),
                width: side,
                height: side)
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

        override func mouseUp(with event: NSEvent) {
            guard self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return }
            self.model.action()
        }

        func setSpinning(_ spinning: Bool) {
            self.isSpinning = spinning
            if spinning {
                guard self.iconView.layer?.animation(forKey: "footerSpin") == nil else { return }
                let animation = CABasicAnimation(keyPath: "transform.rotation.z")
                animation.fromValue = 0
                animation.toValue = -Double.pi * 2
                animation.duration = 0.9
                animation.repeatCount = .infinity
                self.iconView.wantsLayer = true
                self.iconView.layer?.add(animation, forKey: "footerSpin")
            } else {
                self.iconView.layer?.removeAnimation(forKey: "footerSpin")
            }
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
