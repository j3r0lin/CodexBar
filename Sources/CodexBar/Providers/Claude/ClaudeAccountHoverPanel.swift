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

    func show(_ card: ClaudeAccountHoverCard, below button: NSView, isSuppressed: @escaping () -> Bool) {
        guard let window = button.window else { return }
        self.isSuppressed = isSuppressed
        self.anchorRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: card)
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
        return panel
    }
}

struct ClaudeAccountHoverCard: View {
    let name: String
    let snapshot: UsageSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(self.name).font(.system(size: 13, weight: .semibold))
            if let snapshot {
                self.windowRow(snapshot.primary)
                self.windowRow(snapshot.secondary)
                Text(Self.ageText(snapshot.updatedAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("No usage data").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func windowRow(_ window: RateWindow?) -> some View {
        if let window, let used = OverviewCompactAccountRow.used(window) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(Self.windowTitle(window)).font(.system(size: 11))
                    Spacer()
                    Text("\(Int(used.rounded()))%"
                        + (window.resetsAt.map { " · resets in " + OverviewCompactAccountRow.countdown(to: $0, now: Date()) } ?? ""))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.22))
                        Capsule()
                            .fill(Color(nsColor: UsageSeverityPalette.color(usedPercent: used)))
                            .frame(width: proxy.size.width * used / 100)
                    }
                }
                .frame(height: 5)
            }
        }
    }

    private static func windowTitle(_ window: RateWindow) -> String {
        guard let minutes = window.windowMinutes else { return "Window" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) days" }
        if minutes % 60 == 0 { return "\(minutes / 60) hours" }
        return "\(minutes) minutes"
    }

    private static func ageText(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        return minutes < 1 ? "Updated just now" : "Updated \(minutes)m ago"
    }
}
