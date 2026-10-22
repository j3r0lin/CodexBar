import AppKit
import CodexBarCore
import SwiftUI

/// The top of the Overview menu: app icon, title and last-update subtitle on the left, the round
/// refresh and settings buttons on the right. The buttons are real hosted controls; the row itself
/// never highlights.
struct OverviewCardHeaderView: View {
    let title: String
    let updatedText: String
    let width: CGFloat
    @Environment(\.providerCardAction) private var cardAction
    @Environment(\.menuCardRefreshMonitor) private var refreshMonitor

    /// The bundle's own icon once the app is packaged; nil under a test runner (no bundle icon).
    private static var appIcon: NSImage? {
        guard !SettingsStore.isRunningTests else { return nil }
        return NSApplication.shared.applicationIconImage ?? NSImage(named: NSImage.applicationIconName)
    }

    private var isRefreshing: Bool {
        self.refreshMonitor?.isManualRefreshInFlight ?? false
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon = Self.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                // Test hosts have no app bundle to pull the icon from; show a neutral stand-in.
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(self.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(self.updatedText)
                    .font(.system(size: 11))
                    .foregroundStyle(OverviewPalette.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            self.refreshButton
            self.button(systemName: "gearshape", label: L("Settings..."), action: .settings)
        }
        .padding(.horizontal, OverviewCompactAccountRow.horizontalPadding)
        .padding(.vertical, 8)
        .frame(width: self.width, alignment: .leading)
    }

    /// The refresh affordance spins down to a progress indicator while a manual refresh runs, the
    /// same feedback the old footer bar gave through its icon animation.
    private var refreshButton: some View {
        OverviewIconButton(action: .refresh, help: L("Refresh")) {
            Group {
                if self.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    OverviewSymbol.image("arrow.clockwise")
                }
            }
        }
    }

    private func button(
        systemName: String,
        label: String,
        action: MenuDescriptor.MenuAction) -> some View
    {
        OverviewIconButton(action: action, help: label) {
            OverviewSymbol.image(systemName)
        }
    }
}

/// The icon button the Overview header and footer share, hosted so a press reaches the button instead
/// of the menu row. The header's primary actions sit on a filled, stroked square; the footer's rarely
/// used ones stay bare and only show the square under the pointer, so they don't outweigh the status.
struct OverviewIconButton<Label: View>: View {
    enum Weight {
        case primary
        case secondary
    }

    let action: MenuDescriptor.MenuAction
    let help: String
    var weight: Weight = .primary
    @ViewBuilder var label: () -> Label
    @Environment(\.providerCardAction) private var cardAction
    @State private var hovering = false

    private var fillOpacity: Double {
        switch self.weight {
        case .primary: 0.08
        case .secondary: self.hovering ? 0.10 : 0
        }
    }

    var body: some View {
        Button {
            self.cardAction.perform?(self.action)
        } label: {
            self.label()
                .opacity(self.weight == .secondary && !self.hovering ? 0.75 : 1)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(self.fillOpacity)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(self.weight == .primary ? 0.10 : 0), lineWidth: 1))
                .contentShape(Rectangle())
                // A menu window is never key, so hover comes from MouseLocationReader's `.activeAlways`
                // tracking area, as on the menu charts. An overlay (not a background) keeps that area inside
                // this button's 30pt frame instead of the expanded frame SwiftUI gives a background.
                .overlay {
                    if self.weight == .secondary {
                        MouseLocationReader(onMoved: { self.hovering = $0 != nil }, drawsHoverOverlay: true)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(self.help)
        .accessibilityLabel(self.help)
        .menuCardInteractiveControl()
    }
}

enum OverviewSymbol {
    /// One weight and size for every Overview chrome icon, so no button reads heavier than its neighbours.
    static func image(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.85))
    }
}

/// The bottom row of the Overview menu: whether auto-refresh runs on the left, About and Quit on the
/// right as bare icons that only show the header's button square on hover. No line sits above it: the last card's
/// border already closes
/// the content, the same way the header meets the first card.
struct OverviewFooterView: View {
    let autoRefreshOn: Bool
    let aboutHelp: String
    let quitHelp: String
    let width: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(self.autoRefreshOn
                    ? Color(red: 0.24, green: 0.84, blue: 0.44)
                    : OverviewPalette.neutral)
                .frame(width: 7, height: 7)
            Text(self.autoRefreshOn ? L("Auto-refresh on") : L("Auto-refresh off"))
                .font(.system(size: 11))
                .foregroundStyle(OverviewPalette.caption)
                .lineLimit(1)
            Spacer(minLength: 8)
            OverviewIconButton(action: .about, help: self.aboutHelp, weight: .secondary) {
                OverviewSymbol.image("info.circle")
            }
            OverviewIconButton(action: .quit, help: self.quitHelp, weight: .secondary) {
                OverviewSymbol.image("power")
            }
        }
        .padding(.horizontal, OverviewCompactAccountRow.horizontalPadding)
        .padding(.vertical, 6)
        .frame(width: self.width, alignment: .leading)
    }
}

/// A plain one-line row of the Overview panel (the share action, the empty state), drawn in the
/// panel instead of as a native item so the menu material never shows through it.
struct OverviewPanelTextRow: View {
    let title: String
    let width: CGFloat
    var systemImageName: String?
    var isDimmed = false

    var body: some View {
        HStack(spacing: 8) {
            if let systemImageName {
                Image(systemName: systemImageName)
                    .frame(width: 16)
            }
            Text(self.title)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
        .foregroundStyle(self.isDimmed ? OverviewPalette.caption : Color.primary)
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .frame(width: self.width, alignment: .leading)
    }
}
