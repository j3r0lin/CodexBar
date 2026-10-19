import AppKit
import CodexBarCore
import SwiftUI

/// Overview colours: one accent for normal readings, orange from 70% and red from 90%, for both the bar
/// and its number. A 0% reading stays neutral white so an unused window reads as empty, not healthy.
enum OverviewPalette {
    static let accent = Color(red: 0x4F / 255, green: 0xD1 / 255, blue: 0xE8 / 255)
    static let warning = Color(red: 1, green: 0xB3 / 255, blue: 0x40 / 255)
    static let critical = Color(red: 1, green: 0x5A / 255, blue: 0x4F / 255)
    static let caption = Color.white.opacity(0.60)
    /// Reset countdowns read one step brighter than the window labels.
    static let reset = Color.white.opacity(0.60)
    /// Names and idle readings.
    static let neutral = Color.white.opacity(0.55)

    static func color(usedPercent used: Double) -> Color {
        if used >= 90 { return self.critical }
        if used >= 70 { return self.warning }
        return self.accent
    }
}

/// Where a menu item sits in its provider's card: every card is one bordered rounded panel, drawn
/// piecewise by the items it spans because each item is its own view.
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

/// The outline of one item's slice of its provider card: the top piece draws the top edge and both
/// sides, a middle piece draws only the sides, the bottom piece closes the card. Tangent arcs keep
/// the corner direction unambiguous.
struct OverviewCardPieceBorder: Shape {
    let position: OverviewBlockPosition
    var radius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: 0.5, dy: 0.5)
        let r = self.radius
        var path = Path()
        switch self.position {
        case .single:
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: r, height: r))
        case .top:
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                tangent2End: CGPoint(x: rect.minX + r, y: rect.minY),
                radius: r)
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r),
                radius: r)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .middle:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        case .bottom:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            path.addArc(
                tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.minX + r, y: rect.maxY),
                radius: r)
            path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
            path.addArc(
                tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - r),
                radius: r)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        return path
    }
}

extension View {
    /// Draws this item's part of its provider card. The card's own padding lives inside the
    /// background so consecutive items paint one continuous panel; a transparent gap below the
    /// last item keeps cards apart without separator lines.
    func overviewBlock(_ position: OverviewBlockPosition) -> some View {
        let radius: CGFloat = 10
        return self
            .padding(.top, position.roundsTop ? 8 : 0)
            .padding(.bottom, position.roundsBottom ? 6 : 0)
            .background(
                UnevenRoundedRectangle(
                    topLeadingRadius: position.roundsTop ? radius : 0,
                    bottomLeadingRadius: position.roundsBottom ? radius : 0,
                    bottomTrailingRadius: position.roundsBottom ? radius : 0,
                    topTrailingRadius: position.roundsTop ? radius : 0)
                    .fill(Color.white.opacity(0.06)))
            .background(OverviewCardPieceBorder(position: position, radius: radius)
                .stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, OverviewCompactAccountRow.blockInset)
            .padding(.bottom, position.roundsBottom ? OverviewCompactAccountRow.blockGap : 0)
    }

    /// Accent-coloured, upper-case, slightly tracked label used in the detail card's titles.
    func overviewSectionTitleStyle() -> some View {
        self
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.66)
            .textCase(.uppercase)
            .foregroundStyle(OverviewPalette.accent)
    }
}

/// A provider's brand mark on a card: the coloured brand asset when one exists, the monochrome
/// template otherwise, and a generic cube for providers the app has never heard of.
struct OverviewProviderIcon: View {
    let image: NSImage?
    let isTemplate: Bool

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(self.isTemplate ? .template : .original)
                    .scaledToFit()
            } else {
                Image(systemName: "cube")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
            }
        }
        .foregroundStyle(Color.white.opacity(0.9))
        .frame(width: 18, height: 18)
    }
}

/// One Overview row per account: the account or provider name on the left, then one line per window
/// the provider reported, short window first, each with its window label, the percentage, a bar
/// across the free width and the reset countdown.
struct OverviewCompactAccountRow: View {
    let name: String
    let shortWindow: RateWindow?
    let longWindow: RateWindow?
    let width: CGFloat
    /// A lone provider row carries the provider's icon; an account row under a group header does not.
    var namesProvider = false
    var provider: UsageProvider?
    var icon: NSImage?
    var iconIsTemplate = true
    var block: OverviewBlockPosition = .single
    /// A hairline above the row separates it from the previous account inside the same card.
    var showsAccountDivider = false
    /// A provider that only has an error shows it in place of its usage.
    var errorText: String?
    /// The account keeps its readings alongside an error (last-known retention, unstable
    /// identity); the name warns instead of the readings disappearing.
    var showsErrorFlag = false
    /// Magpie rows pass every window the gateway reported, each under its own label, instead of
    /// the short/long slots a native snapshot fills.
    var namedLines: [Line]?
    /// Lone provider cards draw their own detail chevron so it centres on the card instead of
    /// the menu item's frame (the shared payload indicator sits on the item, gap included).
    var showsDetailChevron = false
    /// Native rows let Grok infer a period from the reset time; magpie-sourced windows never do.
    var infersPeriodFromReset = true
    var now = Date()
    @Environment(\.menuItemHighlighted) private var isHighlighted

    struct Line: Equatable {
        let label: String
        let used: Double
        let resetsAt: Date?
    }

    /// Every line puts the same element in the same column, so each part is sized here and the bar
    /// takes whatever the line has left.
    static let blockInset: CGFloat = 8
    /// The transparent gap between two cards.
    static let blockGap: CGFloat = 10
    static let horizontalPadding: CGFloat = 12
    /// Icon plus a provider name; account names under a group header get a narrower column.
    /// Sized so "OpenCode Go" (88pt at 13pt semibold) fits beside the 18pt icon.
    static let providerNameColumn: CGFloat = 124
    static let accountNameColumn: CGFloat = 92
    /// Fits the scoped-weekly model labels ("Fable" is 27pt at 10pt medium) alongside "5h"/"7d"/"Mo".
    static let labelWidth: CGFloat = 32
    /// Fits "100%" at 13pt semibold with monospaced digits.
    static let percentWidth: CGFloat = 38
    /// Fits "resets in 5d 21h" at 10pt with monospaced digits.
    static let resetWidth: CGFloat = 100
    /// Every window line keeps this height so lines pitch evenly within and across accounts.
    static let lineHeight: CGFloat = 22

    /// The windows that have a reading, short first. A window the provider did not report gets no line.
    var lines: [Line] {
        guard self.errorText == nil else { return [] }
        if let namedLines { return namedLines }
        return [self.shortWindow, self.longWindow].compactMap { window in
            guard let window, let used = Self.used(window) else { return nil }
            return Line(
                label: Self.windowLabel(
                    window,
                    provider: self.provider,
                    infersPeriodFromReset: self.infersPeriodFromReset),
                used: used,
                resetsAt: window.resetsAt)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if self.showsAccountDivider {
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.vertical, 3)
            }
            if let errorText {
                self.errorLines(errorText)
            } else {
                HStack(alignment: .center, spacing: 8) {
                    self.nameColumn
                    self.windowLines
                    if self.showsDetailChevron {
                        self.detailChevron
                    }
                }
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .overviewBlock(self.block)
        .frame(width: self.width, alignment: .leading)
    }

    private var nameColumn: some View {
        HStack(spacing: 8) {
            if self.namesProvider {
                OverviewProviderIcon(image: self.icon, isTemplate: self.iconIsTemplate)
            }
            Text(self.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(self.nameColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(
            width: (self.namesProvider ? Self.providerNameColumn : Self.accountNameColumn) - 8,
            alignment: .leading)
    }

    private var nameColor: Color {
        if self.showsErrorFlag { return OverviewPalette.warning }
        return self.namesProvider ? .white : Color.white.opacity(0.85)
    }

    @ViewBuilder
    private var windowLines: some View {
        let lines = self.lines
        if lines.isEmpty {
            self.windowLine { Spacer(minLength: 0) }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines.indices, id: \.self) { index in
                    self.windowLine { self.reading(lines[index]) }
                }
            }
        }
    }

    /// An error-only provider names itself in full on the first line and wraps the message below it,
    /// so neither the name nor the message is truncated into the narrow name column. The name stays
    /// white: the red message carries the error on its own. Icon and chevron centre on the card.
    private func errorLines(_ errorText: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if self.namesProvider {
                OverviewProviderIcon(image: self.icon, isTemplate: self.iconIsTemplate)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(self.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(errorText)
                    .font(.system(size: 10))
                    .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if self.showsDetailChevron {
                self.detailChevron
            }
        }
        .padding(.vertical, 4)
    }

    /// The trailing "›" of a lone provider card, matching the payload indicator's style.
    private var detailChevron: some View {
        Image(systemName: "chevron.forward")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
            .padding(.trailing, 2)
    }

    private func windowLine(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(height: Self.lineHeight)
    }

    private func reading(_ line: Line) -> some View {
        let color = Self.severityColor(line.used)
        return HStack(spacing: 8) {
            Text(line.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(OverviewPalette.caption)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)
            Text("\(Int(line.used.rounded()))%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(line.used > 0 ? color : OverviewPalette.neutral)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: Self.percentWidth, alignment: .trailing)
            UsageBar(used: line.used, color: color, trackColor: Self.trackColor, height: 6)
            Text(line.resetsAt.map { L("resets in %@", Self.countdown(to: $0, now: self.now)) } ?? "—")
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
        let infersPeriod = !snapshot.isMagpieSourced
        let windows = [snapshot.primary, snapshot.secondary, snapshot.tertiary].compactMap(\.self)
        var short = windows.first {
            (Self.nativeMinutes($0, provider: provider, infersPeriodFromReset: infersPeriod) ?? .max) <= 1440
        }
        var long = windows.first {
            (Self.nativeMinutes($0, provider: provider, infersPeriodFromReset: infersPeriod) ?? 0) > 1440
        }
        let unknown = windows.filter {
            Self.nativeMinutes($0, provider: provider, infersPeriodFromReset: infersPeriod) == nil
        }
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
    /// descriptions never determine the quota period. Magpie-sourced windows get no fallback:
    /// their period comes from a known duration or a parseable window name only.
    static func nativeMinutes(
        _ window: RateWindow,
        provider: UsageProvider?,
        infersPeriodFromReset: Bool = true) -> Int?
    {
        if let minutes = window.windowMinutes { return minutes }
        // Provider-specific by design: Grok owns the weekly fallback for its untyped credit pool.
        guard provider == .grok, infersPeriodFromReset else { return nil }
        switch GrokProviderDescriptor.displayLabel(window: window) {
        case "Weekly": return 10080
        case "Monthly": return 43200
        default: return nil
        }
    }

    static func windowLabel(
        _ window: RateWindow,
        provider: UsageProvider?,
        infersPeriodFromReset: Bool = true) -> String
    {
        guard let minutes = nativeMinutes(window, provider: provider, infersPeriodFromReset: infersPeriodFromReset)
        else { return "—" }
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
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}

/// Header of a multi-account provider card: brand icon, the "Provider · N accounts" title, the
/// window kinds the group holds, and the chevron that collapses the account list. Tapping the row
/// toggles the collapse; the row view itself stays passive.
struct OverviewProviderGroupHeader: View {
    let title: String
    let windowHint: String
    let icon: NSImage?
    let iconIsTemplate: Bool
    let collapsed: Bool
    let width: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            OverviewProviderIcon(image: self.icon, isTemplate: self.iconIsTemplate)
            Text(self.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !self.windowHint.isEmpty {
                Text(self.windowHint)
                    .font(.system(size: 10))
                    .foregroundStyle(OverviewPalette.caption)
                    .lineLimit(1)
            }
            Image(systemName: self.collapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(OverviewPalette.caption)
        }
        .padding(.horizontal, OverviewCompactAccountRow.horizontalPadding)
        .padding(.vertical, 5)
        .overviewBlock(self.collapsed ? .single : .top)
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
