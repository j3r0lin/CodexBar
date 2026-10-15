import CodexBarCore
import SwiftUI

/// One Overview line per account: the name, then a lane per window, each with its own bar,
/// percentage and reset time.
struct OverviewCompactAccountRow: View {
    let name: String
    let shortWindow: RateWindow?
    let longWindow: RateWindow?
    let width: CGFloat
    /// Account rows under a provider heading sit further right than a lone provider row.
    var indent: CGFloat = 0
    /// A provider that only has an error shows it in place of its usage.
    var errorText: String?
    var now = Date()
    @Environment(\.menuItemHighlighted) private var isHighlighted

    /// Every row, and the caption line above them, puts the same element in the same column, so each
    /// part is sized here and the bars take whatever the row has left: at 340pt that is 41pt per bar.
    static let nameColumn: CGFloat = 62
    /// Fits "100%", which measures 33.8pt at 12pt.
    static let percentWidth: CGFloat = 36
    static let resetWidth: CGFloat = 38
    static let columnSpacing: CGFloat = 8
    /// The number sits right after its bar so the two read as one reading.
    static let barPercentGap: CGFloat = 4
    static let percentResetGap: CGFloat = 4
    static let horizontalPadding: CGFloat = 8
    /// With 4pt above and below, a row is 22pt tall. A row whose lane is blank keeps this height.
    private static let lineHeight: CGFloat = 14

    var body: some View {
        HStack(spacing: Self.columnSpacing) {
            Text(self.name)
                .font(.system(size: 12, weight: .medium))
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
        .padding(.vertical, 4)
        .frame(width: self.width, alignment: .leading)
    }

    /// A window the provider did not report leaves its lane blank, but the lane keeps its half of the
    /// row so the columns stay put on every line.
    private func lane(window: RateWindow?) -> some View {
        HStack(spacing: 0) {
            if let used = Self.used(window) {
                self.bar(used: used)
                Text("\(Int(used.rounded()))%")
                    .font(.system(size: 12).monospacedDigit())
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

    private func bar(used: Double) -> some View {
        UsageBar(used: used, color: Self.severityColor(used), trackColor: Self.trackColor, height: 5)
    }

    /// Menus are pinned dark, so the empty part of a bar is drawn light enough to read there.
    static let trackColor = Color.white.opacity(0.25)

    /// The bar and its number share one colour, and a highlighted row keeps it: the selection is painted
    /// behind the row, so the reading survives the highlight.
    private static func severityColor(_ used: Double) -> Color {
        Color(nsColor: UsageSeverityPalette.color(usedPercent: used))
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

/// Grey caption above a provider's account rows. It is not a row: no usage, no highlight, no action.
/// The first heading also carries the "5h" and "7d" column captions, each over its lane's percentage
/// column: the title is wider than the name column, so a caption over the bar would collide with it.
struct OverviewAccountGroupHeading: View {
    let title: String
    let width: CGFloat
    var showsColumnCaptions = false

    var body: some View {
        ZStack(alignment: .leading) {
            if self.showsColumnCaptions {
                HStack(spacing: OverviewCompactAccountRow.columnSpacing) {
                    Color.clear.frame(width: OverviewCompactAccountRow.nameColumn, height: 1)
                    OverviewColumnCaptions.laneCaption("5h", overBar: false)
                    OverviewColumnCaptions.laneCaption("7d", overBar: false)
                }
            }
            Text(self.title)
                .lineLimit(1)
                .frame(maxWidth: self.showsColumnCaptions ? self.titleWidth : .infinity, alignment: .leading)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, OverviewCompactAccountRow.horizontalPadding)
        .padding(.top, 4)
        .padding(.bottom, 0)
        .frame(width: self.width, alignment: .leading)
    }

    /// Room left before the first caption, with a 6pt gap.
    private var titleWidth: CGFloat {
        let row = OverviewCompactAccountRow.self
        let lanes = self.width - row.horizontalPadding * 2 - row.nameColumn - row.columnSpacing * 2
        return row.nameColumn + row.columnSpacing + lanes / 2 - OverviewColumnCaptions.trailingColumns - 6
    }
}

/// One grey line above the Overview list naming the two window columns, laid out like a row so each
/// caption sits over the start of its bars. Used when the list does not open with a group heading.
struct OverviewColumnCaptions: View {
    let width: CGFloat

    /// The percentage and reset columns that follow a bar, with their gaps.
    static let trailingColumns = OverviewCompactAccountRow.barPercentGap + OverviewCompactAccountRow.percentWidth
        + OverviewCompactAccountRow.percentResetGap + OverviewCompactAccountRow.resetWidth

    var body: some View {
        HStack(spacing: OverviewCompactAccountRow.columnSpacing) {
            Color.clear.frame(width: OverviewCompactAccountRow.nameColumn, height: 1)
            Self.laneCaption("5h", overBar: true)
            Self.laneCaption("7d", overBar: true)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, OverviewCompactAccountRow.horizontalPadding)
        .padding(.top, 4)
        .frame(width: self.width, alignment: .leading)
    }

    static func laneCaption(_ text: String, overBar: Bool) -> some View {
        HStack(spacing: 0) {
            if overBar {
                Text(text).font(.system(size: 10)).lineLimit(1)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                Text(text)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .padding(.leading, OverviewCompactAccountRow.barPercentGap)
                    .frame(width: Self.trailingColumns, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
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
