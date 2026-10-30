import AppKit
import CodexBarCore
import SwiftUI

/// The Overview's app mark: three bars of different height on a dark rounded square, drawn here so the
/// header doesn't depend on the bundle's terminal-style app icon.
struct OverviewAppGlyph: View {
    var size: CGFloat = 22

    private static let barWidth: CGFloat = 3
    private static let inset: CGFloat = 4
    /// Height of each bar as a share of the room inside the square, with the third one dimmed.
    private static let bars: [(height: CGFloat, opacity: Double)] = [(0.45, 1), (0.80, 1), (0.60, 0.6)]

    var body: some View {
        let room = self.size - Self.inset * 2
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Self.bars.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: Self.barWidth / 2, style: .continuous)
                    .fill(OverviewPalette.accent.opacity(Self.bars[index].opacity))
                    .frame(width: Self.barWidth, height: room * Self.bars[index].height)
            }
        }
        .frame(width: self.size, height: self.size)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(white: 0x2C / 255), Color(white: 0x1B / 255)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// The header subtitle and footer status of the Overview, kept out of the views so they can be checked
/// without rendering.
enum OverviewChromeText {
    /// "Updated 12:02 · Auto-refresh": the clock follows the user's 12/24-hour setting, and a reading
    /// from an earlier day carries its date so it never reads as today's.
    static func updatedSubtitle(
        at date: Date,
        autoRefreshOn: Bool,
        now: Date = Date(),
        locale: Locale = .autoupdatingCurrent,
        calendar: Calendar = .current) -> String
    {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = calendar.isDate(date, inSameDayAs: now) ? .none : .short
        let time = formatter.string(from: date)
        return autoRefreshOn ? L("Updated %@ · Auto-refresh", time) : L("Updated %@", time)
    }

    /// "Auto-refresh on · every 5 min". Adaptive modes have no fixed interval to name, so they keep the
    /// plain "Auto-refresh on".
    static func autoRefreshStatus(_ frequency: RefreshFrequency) -> String {
        if frequency == .manual { return L("Auto-refresh off") }
        guard frequency.seconds != nil else { return L("Auto-refresh on") }
        return L("Auto-refresh on · every %@", frequency.label)
    }
}

/// The top of the Overview menu: app glyph, title and last-update subtitle on the left, the bare
/// refresh and settings buttons on the right. The buttons are real hosted controls; the row itself
/// never highlights.
struct OverviewCardHeaderView: View {
    let title: String
    let updatedText: String
    let width: CGFloat
    @Environment(\.providerCardAction) private var cardAction
    @Environment(\.menuCardRefreshMonitor) private var refreshMonitor

    private var isRefreshing: Bool {
        self.refreshMonitor?.isManualRefreshInFlight ?? false
    }

    var body: some View {
        HStack(spacing: 10) {
            OverviewAppGlyph(size: 22)
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
/// of the menu row. Both are bare icons that only show a square under the pointer; the header's are a
/// step larger and brighten on hover, the footer's rarely used ones stay dimmer so they don't outweigh
/// the status.
struct OverviewIconButton<Label: View>: View {
    enum Weight {
        case primary
        case secondary
    }

    let action: MenuDescriptor.MenuAction
    let help: String
    var weight: Weight = .primary
    var size: CGFloat = 26
    @ViewBuilder var label: () -> Label
    @Environment(\.providerCardAction) private var cardAction
    @State private var hovering = false

    private var hoverStyle: MenuHoverOverlay.Style {
        switch self.weight {
        case .primary: MenuHoverOverlay.Style(opacity: 0.08, cornerRadius: 6)
        case .secondary: .footer
        }
    }

    private var tint: Color {
        switch self.weight {
        case .primary: self.hovering ? OverviewPalette.text : OverviewPalette.caption
        case .secondary: Color.white.opacity(0.85)
        }
    }

    var body: some View {
        Button {
            self.cardAction.perform?(self.action)
        } label: {
            self.label()
                .foregroundStyle(self.tint)
                .opacity(self.weight == .secondary && !self.hovering ? 0.75 : 1)
                .frame(width: self.size, height: self.size)
                .contentShape(Rectangle())
                // A menu window is never key, so hover comes from MouseLocationReader's `.activeAlways`
                // tracking area, as on the menu charts. An overlay (not a background) keeps that area inside
                // this button's frame instead of the expanded frame SwiftUI gives a background.
                .overlay {
                    MouseLocationReader(
                        onMoved: { self.hovering = $0 != nil },
                        drawsHoverOverlay: true,
                        hoverStyle: self.hoverStyle)
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
    }
}

/// The bottom row of the Overview menu: whether auto-refresh runs on the left, About and Quit on the
/// right as bare icons that only show the header's button square on hover. No line sits above it: the last card's
/// border already closes
/// the content, the same way the header meets the first card.
struct OverviewFooterView: View {
    let autoRefreshOn: Bool
    let statusText: String
    let aboutHelp: String
    let quitHelp: String
    let width: CGFloat

    private static let buttonSize: CGFloat = 24

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(self.autoRefreshOn
                    ? Color(red: 0.24, green: 0.84, blue: 0.44)
                    : OverviewPalette.neutral)
                .frame(width: 7, height: 7)
            Text(self.statusText)
                .font(.system(size: 11))
                .foregroundStyle(OverviewPalette.caption)
                .lineLimit(1)
            Spacer(minLength: 8)
            OverviewIconButton(action: .about, help: self.aboutHelp, weight: .secondary, size: Self.buttonSize) {
                OverviewSymbol.image("info.circle")
            }
            OverviewIconButton(action: .quit, help: self.quitHelp, weight: .secondary, size: Self.buttonSize) {
                OverviewSymbol.image("power")
            }
        }
        .padding(.horizontal, OverviewCompactAccountRow.horizontalPadding)
        .padding(.vertical, 2)
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
