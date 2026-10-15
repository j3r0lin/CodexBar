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
    var now = Date()
    @Environment(\.menuItemHighlighted) private var isHighlighted

    /// Every row has to put the same element in the same column, so each part is sized here and the
    /// bars take whatever the row has left.
    private static let nameColumn: CGFloat = 62
    private static let labelWidth: CGFloat = 14
    private static let percentWidth: CGFloat = 32
    private static let resetWidth: CGFloat = 38
    private static let columnSpacing: CGFloat = 10
    private static let laneSpacing: CGFloat = 5
    /// A row is 28pt tall. The bars are only 5pt, so the line box around them is what sets the row's
    /// height, and a row whose lane is blank has to keep the height of a row that carries a bar.
    private static let lineHeight: CGFloat = 18

    var body: some View {
        HStack(spacing: Self.columnSpacing) {
            Text(self.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(width: Self.nameColumn - self.indent, alignment: .leading)
                .padding(.leading, self.indent)
            self.lane(label: "5h", window: self.shortWindow)
            self.lane(label: "7d", window: self.longWindow)
        }
        .frame(height: Self.lineHeight)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(width: self.width, alignment: .leading)
    }

    /// A window the provider did not report leaves its lane blank, but the lane keeps its half of the
    /// row so the 5h and 7d columns stay put on every line.
    private func lane(label: String, window: RateWindow?) -> some View {
        HStack(spacing: Self.laneSpacing) {
            if let used = Self.used(window) {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .frame(width: Self.labelWidth, alignment: .leading)
                self.bar(used: used)
                Text("\(Int(used.rounded()))%")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Self.severityColor(used))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: Self.percentWidth, alignment: .trailing)
                Text(self.resetText(window))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: Self.resetWidth, alignment: .leading)
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
            .padding(.top, 8)
            .padding(.bottom, 2)
            .frame(width: self.width, alignment: .leading)
    }
}
