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
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Self.trackColor)
                Capsule()
                    .fill(Self.severityColor(used))
                    .frame(width: proxy.size.width * min(1, max(0, used / 100)))
            }
        }
        .frame(height: 5)
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
struct OverviewAccountGroupHeading: View {
    let title: String
    let width: CGFloat

    var body: some View {
        Text(self.title)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .padding(.bottom, 0)
            .frame(width: self.width, alignment: .leading)
    }
}

/// One grey line above the Overview list naming the two window columns, laid out like a row so each
/// caption sits over the start of its bars.
struct OverviewColumnCaptions: View {
    let width: CGFloat

    var body: some View {
        HStack(spacing: OverviewCompactAccountRow.columnSpacing) {
            Color.clear.frame(width: OverviewCompactAccountRow.nameColumn, height: 1)
            self.caption("5h")
            self.caption("7d")
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, OverviewCompactAccountRow.horizontalPadding)
        .padding(.top, 4)
        .frame(width: self.width, alignment: .leading)
    }

    private func caption(_ text: String) -> some View {
        Text(text).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
    }
}
