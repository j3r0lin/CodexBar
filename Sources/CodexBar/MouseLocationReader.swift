import AppKit
import SwiftUI

/// Draws the hover square of the Overview's icon buttons in AppKit. NSMenu tracking neither drains the main
/// queue nor repaints a SwiftUI hosting view, so the SwiftUI hover state cannot become visible on its own;
/// `refreshHostedContent` pushes it through.
@MainActor
enum MenuHoverOverlay {
    static func update(around view: NSView, hovering: Bool, style: Style = .footer) {
        guard let container = sequence(first: view, next: { $0.superview })
            .first(where: { $0 is MenuRowContainerView })
        else { return }
        let frame = view.convert(view.bounds, to: container)
        let existing = container.subviews.compactMap { $0 as? HoverView }
        if hovering {
            let overlay = existing.first ?? HoverView()
            overlay.frame = frame
            overlay.apply(style)
            if overlay.superview !== container {
                container.addSubview(overlay, positioned: .below, relativeTo: nil)
            }
        } else {
            existing.forEach { $0.removeFromSuperview() }
        }
    }

    /// Lays out and redraws the hosting view around `view`, so SwiftUI state set by the tracking callback
    /// (the icon tint) shows while the menu is still tracking.
    static func refreshHostedContent(around view: NSView) {
        guard let container = sequence(first: view, next: { $0.superview })
            .first(where: { $0 is MenuRowContainerView })
        else { return }
        container.layoutSubtreeIfNeeded()
        container.displayIfNeeded()
    }

    struct Style: Equatable {
        var opacity: CGFloat
        var cornerRadius: CGFloat

        static let footer = Style(opacity: 0.10, cornerRadius: 8)
    }

    final class HoverView: NSView {
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.wantsLayer = true
            self.apply(.footer)
        }

        func apply(_ style: Style) {
            self.layer?.backgroundColor = NSColor.white.withAlphaComponent(style.opacity).cgColor
            self.layer?.cornerRadius = style.cornerRadius
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    }
}

/// Lightweight NSView-based mouse tracking with local coordinates.
///
/// Why: SwiftUI's `onHover` doesn't provide location, but we want "hover a bar to see values" on macOS.
@MainActor
struct MouseLocationReader: NSViewRepresentable {
    let onMoved: (CGPoint?) -> Void
    var drawsHoverOverlay = false
    var hoverStyle = MenuHoverOverlay.Style.footer

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMoved = self.onMoved
        view.drawsHoverOverlay = self.drawsHoverOverlay
        view.hoverStyle = self.hoverStyle
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onMoved = self.onMoved
        nsView.drawsHoverOverlay = self.drawsHoverOverlay
        nsView.hoverStyle = self.hoverStyle
    }

    final class TrackingView: NSView {
        var onMoved: ((CGPoint?) -> Void)?
        var drawsHoverOverlay = false
        var hoverStyle = MenuHoverOverlay.Style.footer
        private var trackingArea: NSTrackingArea?

        override var isFlipped: Bool {
            true
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            self.window?.acceptsMouseMovedEvents = true
            self.updateTrackingAreas()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                self.removeTrackingArea(trackingArea)
            }

            let options: NSTrackingArea.Options = [
                // NSMenu popups aren't "key windows", so `.activeInKeyWindow` would drop events and cause hover
                // state to flicker. `.activeAlways` keeps tracking stable while the menu is open.
                .activeAlways,
                .inVisibleRect,
                .mouseEnteredAndExited,
                .mouseMoved,
            ]
            let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
            self.addTrackingArea(area)
            self.trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            self.report(self.convert(event.locationInWindow, from: nil))
        }

        override func mouseMoved(with event: NSEvent) {
            super.mouseMoved(with: event)
            self.report(self.convert(event.locationInWindow, from: nil))
        }

        private func report(_ location: CGPoint?) {
            self.onMoved?(location)
            if self.drawsHoverOverlay {
                MenuHoverOverlay.update(around: self, hovering: location != nil, style: self.hoverStyle)
                MenuHoverOverlay.refreshHostedContent(around: self)
            }
        }

        /// The footer reader covers its button. A hit would stop the menu row from forwarding the press
        /// to that button, so pointer tracking stays active while clicks pass through.
        override func hitTest(_ point: NSPoint) -> NSView? {
            self.drawsHoverOverlay ? nil : super.hitTest(point)
        }

        override func mouseExited(with event: NSEvent) {
            super.mouseExited(with: event)
            self.report(nil)
        }
    }
}
