import CodexBarCore
import SwiftUI

/// Overview colours: one accent for normal readings, orange from 70% and red from 90%, for both the bar
/// and its number. Provider and group names use the accent too.
enum OverviewPalette {
    static let accent = Color(red: 0x4F / 255, green: 0xD1 / 255, blue: 0xE8 / 255)
    static let warning = Color(red: 1, green: 0xB3 / 255, blue: 0x40 / 255)
    static let critical = Color(red: 1, green: 0x5A / 255, blue: 0x4F / 255)
    static let caption = Color.white.opacity(0.60)
    /// Reset countdowns read one step brighter than the window labels.
    static let reset = Color.white.opacity(0.60)

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
    /// Draws this item's part of its provider block. The block's own padding lives inside the
    /// background so consecutive items paint one continuous panel; a 6pt transparent gap below
    /// the last item keeps blocks apart without separator lines.
    func overviewBlock(_ position: OverviewBlockPosition) -> some View {
        let radius: CGFloat = 8
        return self
            .padding(.top, position.roundsTop ? 6 : 0)
            .padding(.bottom, position.roundsBottom ? 4 : 0)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: position.roundsTop ? radius : 0,
                    bottomLeadingRadius: position.roundsBottom ? radius : 0,
                    bottomTrailingRadius: position.roundsBottom ? radius : 0,
                    topTrailingRadius: position.roundsTop ? radius : 0)
                    .fill(Color.white.opacity(0.07)))
            .padding(.horizontal, OverviewCompactAccountRow.blockInset)
            .padding(.bottom, position.roundsBottom ? 6 : 0)
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

/// One Overview row per account: a line per window the provider reported, short window first, each with
/// its window label, a bar across the free width, the percentage and the reset time. The name sits on the
/// first line only.
struct OverviewCompactAccountRow: View {
    let name: String
    let shortWindow: RateWindow?
    let longWindow: RateWindow?
    let width: CGFloat
    /// Account rows under a provider heading sit further right than a lone provider row.
    var indent: CGFloat = 0
    /// A lone provider row names its provider in the section-title style; an account row names its account.
    var namesProvider = false
    var provider: UsageProvider?
    var block: OverviewBlockPosition = .single
    /// A provider that only has an error shows it in place of its usage.
    var errorText: String?
    var now = Date()
    @Environment(\.menuItemHighlighted) private var isHighlighted

    struct Line: Equatable {
        let label: String
        let used: Double
        let resetsAt: Date?
    }

    /// Every line puts the same element in the same column, so each part is sized here and the bar takes
    /// whatever the line has left.
    static let blockInset: CGFloat = 2
    static let horizontalPadding: CGFloat = 8
    /// Fits "KIMI CODE" in the section-title style.
    static let nameColumn: CGFloat = 88
    static let labelWidth: CGFloat = 20
    /// Fits "100%" at 13pt semibold with monospaced digits.
    static let percentWidth: CGFloat = 38
    static let resetWidth: CGFloat = 40
    /// Every window line keeps this height so lines pitch evenly within and across accounts.
    static let lineHeight: CGFloat = 22

    /// The windows that have a reading, short first. A window the provider did not report gets no line.
    var lines: [Line] {
        guard self.errorText == nil else { return [] }
        return [self.shortWindow, self.longWindow].compactMap { window in
            guard let window, let used = Self.used(window) else { return nil }
            return Line(label: Self.windowLabel(window, provider: self.provider), used: used, resetsAt: window.resetsAt)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let lines = self.lines
            if let errorText {
                self.errorLines(errorText)
            } else if lines.isEmpty {
                self.line(named: true) { Spacer(minLength: 0) }
            } else {
                ForEach(lines.indices, id: \.self) { index in
                    self.line(named: index == 0) { self.reading(lines[index]) }
                }
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .overviewBlock(self.block)
        .frame(width: self.width, alignment: .leading)
    }

    /// An error-only provider names itself in full on the first line and wraps the message below it,
    /// so neither the name nor the message is truncated into the narrow name column.
    private func errorLines(_ errorText: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(self.name)
                .overviewSectionTitleStyle()
                .lineLimit(1)
            Text(errorText)
                .font(.system(size: 10))
                .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    private func line(named: Bool, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) {
            Group {
                if named {
                    self.nameLabel
                } else {
                    Color.clear
                }
            }
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(width: Self.nameColumn - self.indent, alignment: .leading)
            .padding(.leading, self.indent)
            content()
        }
        .frame(height: Self.lineHeight)
    }

    @ViewBuilder
    private var nameLabel: some View {
        if self.namesProvider {
            Text(self.name).overviewSectionTitleStyle()
        } else {
            Text(self.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white)
        }
    }

    private func reading(_ line: Line) -> some View {
        let color = Self.severityColor(line.used)
        return HStack(spacing: 8) {
            Text(line.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(OverviewPalette.caption)
                .frame(width: Self.labelWidth, alignment: .leading)
            UsageBar(used: line.used, color: color, trackColor: Self.trackColor, height: 6)
            Text("\(Int(line.used.rounded()))%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: Self.percentWidth, alignment: .trailing)
            Text(line.resetsAt.map { Self.countdown(to: $0, now: self.now) } ?? "")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(OverviewPalette.reset)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: Self.resetWidth, alignment: .leading)
        }
    }

    /// Menus are pinned dark, so the empty part of a bar is drawn light enough to read there.
    static let trackColor = Color.white.opacity(0.14)

    /// The bar and its number share one colour, and a highlighted row keeps it: the selection is painted
    /// behind the row, so the reading survives the highlight.
    static func severityColor(_ used: Double) -> Color {
        OverviewPalette.color(usedPercent: used)
    }

    /// Explicit durations determine the slots. Untyped readings use only provider-owned semantics;
    /// an unknown reading occupies the long slot first and keeps a duration-free label.
    static func slots(
        of snapshot: UsageSnapshot?,
        provider: UsageProvider? = nil) -> (short: RateWindow?, long: RateWindow?)
    {
        guard let snapshot else { return (nil, nil) }
        let windows = [snapshot.primary, snapshot.secondary, snapshot.tertiary].compactMap(\.self)
        var short = windows.first { (Self.nativeMinutes($0, provider: provider) ?? .max) <= 1440 }
        var long = windows.first { (Self.nativeMinutes($0, provider: provider) ?? 0) > 1440 }
        let unknown = windows.filter { Self.nativeMinutes($0, provider: provider) == nil }
        for window in unknown {
            if long == nil {
                long = window
            } else if short == nil {
                short = window
            }
        }
        return (short, long)
    }

    /// Grok's descriptor owns the fallback for its untyped credit pool; human-readable reset
    /// descriptions never determine the quota period.
    static func nativeMinutes(_ window: RateWindow, provider: UsageProvider?) -> Int? {
        if let minutes = window.windowMinutes { return minutes }
        // Provider-specific by design: Grok owns the weekly fallback for its untyped credit pool.
        guard provider == .grok else { return nil }
        switch GrokProviderDescriptor.displayLabel(window: window) {
        case "Weekly": return 10080
        case "Monthly": return 43200
        default: return nil
        }
    }

    static func windowLabel(_ window: RateWindow, provider: UsageProvider?) -> String {
        guard let minutes = nativeMinutes(window, provider: provider) else { return "—" }
        if minutes >= 28 * 1440 { return "Mo" }
        if minutes >= 1440 { return "\(minutes / 1440)d" }
        return "\(max(1, minutes / 60))h"
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
            .frame(height: 16)
            .padding(.horizontal, OverviewCompactAccountRow.horizontalPadding)
            .padding(.bottom, 2)
            .overviewBlock(.top)
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
