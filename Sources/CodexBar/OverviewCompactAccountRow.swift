import CodexBarCore
import SwiftUI

/// One Overview line per account: name, short-window ring, long-window bar, long-window reset.
struct OverviewCompactAccountRow: View {
    let name: String
    let shortWindow: RateWindow?
    let longWindow: RateWindow?
    let width: CGFloat
    /// Account rows under a provider heading sit further right than a lone provider row.
    var indent: CGFloat = 0
    var now = Date()
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(self.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .frame(width: 60 - self.indent, alignment: .leading)
                .padding(.leading, self.indent)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 3) {
                    if let used = Self.used(self.shortWindow) {
                        OverviewUsageRing(usedPercent: used)
                            .frame(width: 16, height: 16)
                        Text("\(Int(used.rounded()))%")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Color(nsColor: UsageSeverityPalette.color(usedPercent: used)))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(height: 16)
                self.resetLine(self.shortWindow)
            }
            .frame(width: 54)
            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 6) {
                    if let used = Self.used(self.longWindow) {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Self.trackColor)
                                Capsule()
                                    .fill(Color(nsColor: UsageSeverityPalette.color(usedPercent: used)))
                                    .frame(width: proxy.size.width * min(1, max(0, used / 100)))
                            }
                        }
                        .frame(height: 5)
                        Text("\(Int(used.rounded()))%")
                            .font(.system(size: 11).monospacedDigit())
                            .frame(width: 34, alignment: .trailing)
                    } else {
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 16)
                self.resetLine(self.longWindow)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, UsageMenuCardLayout.horizontalPadding)
        .padding(.vertical, 4)
        .frame(width: self.width, alignment: .leading)
    }

    /// Menus are pinned dark, so the empty part of a ring or bar is drawn light enough to read there.
    static let trackColor = Color.white.opacity(0.25)

    /// A window without a reset time keeps an empty line so every row has the same height.
    private func resetLine(_ window: RateWindow?) -> some View {
        let text = Self.used(window) == nil ? nil : window?.resetsAt.map { Self.countdown(to: $0, now: self.now) }
        return Text(text ?? " ")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// A placeholder window stands for a lane the provider did not report, so it gets no number.
    static func used(_ window: RateWindow?) -> Double? {
        guard let window, !window.isSyntheticPlaceholder else { return nil }
        return min(100, max(0, window.usedPercent))
    }

    static func countdown(to date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
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
            .padding(.horizontal, UsageMenuCardLayout.horizontalPadding)
            .padding(.top, 6)
            .padding(.bottom, 1)
            .frame(width: self.width, alignment: .leading)
    }
}

struct OverviewUsageRing: View {
    let usedPercent: Double

    var body: some View {
        ZStack {
            Circle().stroke(OverviewCompactAccountRow.trackColor, lineWidth: 2.2)
            Circle()
                .trim(from: 0, to: min(1, max(0, self.usedPercent / 100)))
                .stroke(
                    Color(nsColor: UsageSeverityPalette.color(usedPercent: self.usedPercent)),
                    style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
