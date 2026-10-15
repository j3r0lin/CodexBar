import AppKit
import CodexBarCore
import SwiftUI

/// A non-activating panel under a menu-bar ring. It opens on mouse enter and closes by sampling the pointer,
/// because closing on mouse exit flickers when the panel itself appears under the pointer.
@MainActor
final class ClaudeAccountHoverPanelController {
    private var panel: NSPanel?
    private var timer: Timer?
    private var anchorRect: NSRect = .zero
    private var outsideSince: Date?
    private var isSuppressed: () -> Bool = { false }
    private static let grace: TimeInterval = 0.3

    func show(_ card: some View, below button: NSView, isSuppressed: @escaping () -> Bool) {
        guard let window = button.window else { return }
        self.isSuppressed = isSuppressed
        self.anchorRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: card
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10)))
        hosting.frame.size = hosting.fittingSize
        panel.contentView = hosting
        let size = hosting.fittingSize
        panel.setFrame(
            NSRect(
                x: self.anchorRect.midX - size.width / 2,
                y: self.anchorRect.minY - size.height - 4,
                width: size.width,
                height: size.height),
            display: true)
        panel.orderFrontRegardless()
        self.outsideSince = nil
        if self.timer == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sample() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func hide() {
        self.timer?.invalidate()
        self.timer = nil
        self.outsideSince = nil
        self.panel?.orderOut(nil)
    }

    private func sample() {
        guard let panel, !self.isSuppressed() else {
            self.hide()
            return
        }
        let pointer = NSEvent.mouseLocation
        let inside = self.anchorRect.insetBy(dx: -2, dy: -2).contains(pointer)
            || panel.frame.insetBy(dx: -2, dy: -6).contains(pointer)
        if inside {
            self.outsideSince = nil
        } else if let since = self.outsideSince {
            if Date().timeIntervalSince(since) >= Self.grace { self.hide() }
        } else {
            self.outsideSince = Date()
        }
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = StatusMenuAppearance.menuAppearance
        return panel
    }
}
