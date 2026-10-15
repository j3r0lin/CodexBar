import CodexBarCore
import SwiftUI

/// Overview colours: one accent for normal readings, orange from 70% and red from 90%, for both the bar
/// and its number. Provider and group names use the accent too.
enum OverviewPalette {
    static let accent = Color(red: 0x4F / 255, green: 0xD1 / 255, blue: 0xE8 / 255)
    static let warning = Color(red: 1, green: 0xB3 / 255, blue: 0x40 / 255)
    static let critical = Color(red: 1, green: 0x5A / 255, blue: 0x4F / 255)
    static let caption = Color(red: 0x6B / 255, green: 0x71 / 255, blue: 0x80 / 255)

    static func color(usedPercent used: Double) -> Color {
        if used >= 90 { return self.critical }
        if used >= 70 { return self.warning }
        return self.accent
    }
}

/// Where a menu item sits in its provider's block: every block is one tinted rounded panel, drawn piecewise
/// by the items it spans because each item is its own view.
enum OverviewBlockPosition {
    case single
    case top
    case middle
    case bottom

    var roundsTop: Bool {
        self == .single || self == .top
    }

    var roundsBottom: Bool {
        self == .single || self == .bottom
    }
}

extension View {
    /// Draws this item's part of its provider block, leaving a 3pt gap above the first and below the last
    /// item so blocks read as separate without separator lines.
    func overviewBlock(_ position: OverviewBlockPosition) -> some View {
        let radius: CGFloat = 8
        return self
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: position.roundsTop ? radius : 0,
                    bottomLeadingRadius: position.roundsBottom ? radius : 0,
                    bottomTrailingRadius: position.roundsBottom ? radius : 0,
                    topTrailingRadius: position.roundsTop ? radius : 0)
                    .fill(Color.white.opacity(0.035)))
            .padding(.horizontal, OverviewCompactAccountRow.blockInset)
            .padding(.top, position.roundsTop ? 3 : 0)
            .padding(.bottom, position.roundsBottom ? 3 : 0)
    }

    /// Accent-coloured, upper-case, slightly tracked label used for provider and group names.
    func overviewSectionTitleStyle() -> some View {
        self
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.66)
            .textCase(.uppercase)
            .foregroundStyle(OverviewPalette.accent)
    }
}

/// One Overview line per account: the name, then a lane per window, each with its own bar,
/// percentage and reset time.
struct OverviewCompactAccountRow: View {
    let name: String
    let shortWindow: RateWindow?
    let longWindow: RateWindow?
    let width: CGFloat
    /// Account rows under a provider heading sit further right than a lone provider row.
    var indent: CGFloat = 0
    /// A lone provider row names its provider in the section-title style; an account row names its account.
    var namesProvider = false
    var block: OverviewBlockPosition = .single
    /// A provider that only has an error shows it in place of its usage.
    var errorText: String?
    var now = Date()
    @Environment(\.menuItemHighlighted) private var isHighlighted

    /// Every row, and the caption line above them, puts the same element in the same column, so each
    /// part is sized here and the bars take whatever the row has left: at 340pt that is 39pt per bar.
    static let blockInset: CGFloat = 4
    static let horizontalPadding: CGFloat = 6
    static let nameColumn: CGFloat = 66
    /// Fits "100%" at 15pt semibold with monospaced digits.
    static let percentWidth: CGFloat = 43
    /// Fits "6d22h" at 10pt.
    static let resetWidth: CGFloat = 32
    static let columnSpacing: CGFloat = 6
    /// The number sits right after its bar so the two read as one reading.
    static let barPercentGap: CGFloat = 3
    static let percentResetGap: CGFloat = 4
    /// With 3pt above and below, a row is 24pt tall inside its block. A blank lane keeps this height.
    private static let lineHeight: CGFloat = 18

    var body: some View {
        HStack(spacing: Self.columnSpacing) {
            self.nameLabel
                .lineLimit(1)
                .frame(width: Self.nameColumn - self.indent, alignment: .leading)
                .padding(.leading, self.indent)
            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                self.lane(window: self.shortWindow)
                self.lane(window: self.longWindow)
            }
        }
        .frame(height: Self.lineHeight)
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 3)
        .overviewBlock(self.block)
        .frame(width: self.width, alignment: .leading)
    }

    @ViewBuilder
    private var nameLabel: some View {
        if self.namesProvider {
            Text(self.name).overviewSectionTitleStyle()
        } else {
            Text(self.name).font(.system(size: 12, weight: .medium))
        }
    }

    /// A window the provider did not report leaves its lane blank, but the lane keeps its half of the
    /// row so the columns stay put on every line.
    private func lane(window: RateWindow?) -> some View {
        HStack(spacing: 0) {
            if let used = Self.used(window) {
                UsageBar(used: used, color: Self.severityColor(used), trackColor: Self.trackColor, height: 5)
                Text("\(Int(used.rounded()))%")
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Self.severityColor(used))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: Self.percentWidth, alignment: .leading)
                    .padding(.leading, Self.barPercentGap)
                Text(self.resetText(window))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: Self.resetWidth, alignment: .leading)
                    .padding(.leading, Self.percentResetGap)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Menus are pinned dark, so the empty part of a bar is drawn light enough to read there.
    static let trackColor = Color.white.opacity(0.18)

    /// The bar and its number share one colour, and a highlighted row keeps it: the selection is painted
    /// behind the row, so the reading survives the highlight.
    static func severityColor(_ used: Double) -> Color {
        OverviewPalette.color(usedPercent: used)
    }

    private func resetText(_ window: RateWindow?) -> String {
        guard Self.used(window) != nil, let resetsAt = window?.resetsAt else { return "" }
        return Self.countdown(to: resetsAt, now: self.now)
    }

    /// Places windows by duration: up to a day is the short slot, longer is the long slot. Only a window
    /// without a duration falls back to its position (primary short, secondary long), because a provider
    /// with a single weekly window still reports it as primary.
    static func slots(of snapshot: UsageSnapshot?) -> (short: RateWindow?, long: RateWindow?) {
        guard let snapshot else { return (nil, nil) }
        let windows = [snapshot.primary, snapshot.secondary, snapshot.tertiary].compactMap(\.self)
        let short = windows.first { ($0.windowMinutes ?? .max) <= 1440 }
            ?? snapshot.primary.flatMap { $0.windowMinutes == nil ? $0 : nil }
        let long = windows.first { ($0.windowMinutes ?? 0) > 1440 }
            ?? snapshot.secondary.flatMap { $0.windowMinutes == nil ? $0 : nil }
        return (short, long)
    }

    /// A placeholder window stands for a lane the provider did not report, so it gets no number.
    static func used(_ window: RateWindow?) -> Double? {
        guard let window, !window.isSyntheticPlaceholder else { return nil }
        return min(100, max(0, window.usedPercent))
    }

    static func countdown(to date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return "\(hours)h\(mins)m" }
        return "\(mins)m"
    }
}

/// Title at the top of a provider's block when it has several accounts. It is not a row: no usage,
/// no highlight, no action.
struct OverviewAccountGroupHeading: View {
    let title: String
    let width: CGFloat

    var body: some View {
        Text(self.title)
            .overviewSectionTitleStyle()
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OverviewCompactAccountRow.horizontalPadding)
            .padding(.top, 6)
            .padding(.bottom, 1)
            .overviewBlock(.top)
            .frame(width: self.width, alignment: .leading)
    }
}

/// One line at the top of the Overview list naming the two window columns, each centred over its lane.
/// It sits on its own line because an upper-case group title is wider than the name column and would
/// run into a caption on the same line.
struct OverviewColumnCaptions: View {
    let width: CGFloat

    var body: some View {
        HStack(spacing: OverviewCompactAccountRow.columnSpacing) {
            Color.clear.frame(width: OverviewCompactAccountRow.nameColumn, height: 1)
            Text("5H").frame(maxWidth: .infinity)
            Text("7D").frame(maxWidth: .infinity)
        }
        .font(.system(size: 10, weight: .medium))
        .tracking(0.6)
        .foregroundStyle(OverviewPalette.caption)
        .lineLimit(1)
        .padding(.horizontal, OverviewCompactAccountRow.horizontalPadding)
        .padding(.top, 4)
        .padding(.horizontal, OverviewCompactAccountRow.blockInset)
        .frame(width: self.width, alignment: .leading)
    }
}

/// A capsule track with its fill drawn as a rectangle clipped to the track, so a small reading keeps
/// the track's rounded left end instead of collapsing into a sliver. Any reading above 0% is at least
/// as wide as the bar is tall, so it shows as a coloured dot; 0% shows no fill.
struct UsageBar: View {
    let used: Double
    let color: Color
    let trackColor: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(self.trackColor)
                Rectangle()
                    .fill(self.color)
                    .frame(width: Self.fillWidth(used: self.used, barWidth: proxy.size.width, height: self.height))
            }
            .clipShape(Capsule())
        }
        .frame(height: self.height)
    }

    static func fillWidth(used: Double, barWidth: CGFloat, height: CGFloat) -> CGFloat {
        guard used > 0 else { return 0 }
        let width = barWidth * min(1, used / 100)
        return min(barWidth, max(height, width))
    }
}
