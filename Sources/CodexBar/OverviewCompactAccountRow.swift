import AppKit
import CodexBarCore
import SwiftUI

/// Overview colours: the bar is the accent for normal readings, orange from the user's first quota-warning
/// threshold and red from the second; its number stays in the primary text colour until it reaches one of
/// them. Without configured thresholds they fall back to 70% and 90%.
enum OverviewPalette {
    /// Fills the whole Overview panel behind its rows: opaque, so the menu material never tints it.
    static let panelBase = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)

    /// Readings that are not a warning.
    static let text = Color.white.opacity(0.92)

    static let accent = Color(red: 0x4F / 255, green: 0xD1 / 255, blue: 0xE8 / 255)
    static let warning = Color(red: 1, green: 0xB3 / 255, blue: 0x40 / 255)
    static let critical = Color(red: 1, green: 0x5A / 255, blue: 0x4F / 255)
    static let caption = Color.white.opacity(0.60)
    /// Secondary names beside a title.
    static let faint = Color.white.opacity(0.38)
    /// Reset countdowns read one step brighter than the window labels.
    static let reset = Color.white.opacity(0.60)
    /// Names and idle readings.
    static let neutral = Color.white.opacity(0.55)
    /// A quota curve's shading where more is left than an even burn would leave.
    static let reserve = Color(red: 0.24, green: 0.84, blue: 0.44)

    /// Used-percent thresholds above which the reading turns orange and red. `thresholds` are the
    /// user's remaining-quota warning thresholds, highest first; converted to the used scale, the
    /// lower one warns and the higher one turns critical. A single threshold leaves red at 90% used,
    /// and nil, or only disabled (0) thresholds, keep 70/90.
    static func bounds(forWarningThresholds thresholds: [Int]?) -> (warning: Double, critical: Double) {
        let active = thresholds.map(QuotaWarningThresholds.active) ?? []
        guard let highestRemaining = active.first else { return (warning: 70, critical: 90) }
        let lowestRemaining = active.last ?? highestRemaining
        return (
            warning: 100 - Double(highestRemaining),
            critical: highestRemaining == lowestRemaining ? 90 : 100 - Double(lowestRemaining))
    }

    static func color(usedPercent used: Double, warningThresholds: [Int]? = nil) -> Color {
        let bounds = self.bounds(forWarningThresholds: warningThresholds)
        if used >= bounds.critical { return self.critical }
        if used >= bounds.warning { return self.warning }
        return self.accent
    }

    /// The number beside a bar: white until the reading reaches a warning threshold.
    static func percentColor(usedPercent used: Double, warningThresholds: [Int]? = nil) -> Color {
        let bounds = self.bounds(forWarningThresholds: warningThresholds)
        if used >= bounds.critical { return self.critical }
        if used >= bounds.warning { return self.warning }
        return self.text
    }
}

extension View {
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

/// How the user wants Overview readings drawn; shared by the compact card and its detail card.
struct OverviewDisplayOptions: Equatable {
    /// Shows the remaining quota instead of the used one. Severity and pace stay keyed on the used
    /// reading, so flipping the display never changes a colour or a pace verdict.
    var showsRemaining = false
    /// The user's remaining-quota warning thresholds, highest first, per window kind; nil keeps 70/90.
    var sessionWarningThresholds: [Int]?
    var weeklyWarningThresholds: [Int]?
    /// Draws the pace tick and the hatching of usage ahead of it; off hides both.
    var showsPace = true

    func warningThresholds(for window: QuotaWarningWindow) -> [Int]? {
        switch window {
        case .session: self.sessionWarningThresholds
        case .weekly: self.weeklyWarningThresholds
        }
    }
}

/// One Overview row per account: a compact header above full-width usage lines, short window first.
struct OverviewCompactAccountRow: View {
    let name: String
    let shortWindow: RateWindow?
    let longWindow: RateWindow?
    let width: CGFloat
    /// Shows the provider icon beside the name.
    var namesProvider = false
    var provider: UsageProvider?
    var icon: NSImage?
    var iconIsTemplate = true
    /// The provider's id, shown in grey beside a name that does not already say it.
    var providerTag: String?
    /// Magpie rows: the account's plan, drawn as a small tag after the name.
    var plan: String?
    /// A hairline under the row separates it from the next account; the last row has none.
    var showsDivider = true
    /// A provider that only has an error shows it in place of its usage.
    var errorText: String?
    /// The account keeps its readings alongside an error (last-known retention, unstable
    /// identity); the name warns instead of the readings disappearing.
    var showsErrorFlag = false
    /// Magpie rows pass their windows as lines, each under its own label, instead of the short/long
    /// slots a native snapshot fills.
    var namedLines: [Line]?
    /// Native rows let Grok infer a period from the reset time; magpie-sourced windows never do.
    var infersPeriodFromReset = true
    var display = OverviewDisplayOptions()
    /// The reading is older than the refresh cadence allows; its numbers are drawn dimmed.
    var isStale = false
    var resetCredits: MagpieResetCredits?
    /// A Codex reset announced for a future time; the caller passes it only for Codex rows.
    var scheduledResetAt: Date?
    var updatedAt: Date?
    var now = Date()
    @Environment(\.menuItemHighlighted) private var isHighlighted

    struct Line: Equatable {
        let label: String
        let used: Double
        let resetsAt: Date?
        /// Which warning thresholds colour this line; a window of unknown length follows the weekly
        /// lane, since it is never the five-hour session.
        var warningWindow: QuotaWarningWindow = .weekly
        /// Where the linear pace says usage should be by now, drawn as a tick on the bar; nil when the
        /// window has no pace.
        var pacePercent: Double?
    }

    /// Every line puts the same element in the same column, so each part is sized here and the bar
    /// takes whatever the line has left.
    static let horizontalPadding: CGFloat = 12
    /// Row content starts here, in line with the usage card above the list.
    static let contentInset: CGFloat = 20
    /// Air above and below an account's lines inside its row.
    static let verticalPadding: CGFloat = 8
    /// Fits the scoped-weekly model labels ("Fable" is 27pt at 10pt medium) alongside "5h"/"7d"/"30d".
    static let labelWidth: CGFloat = 32
    /// Fits "100%" at 13pt semibold with monospaced digits.
    static let percentWidth: CGFloat = 38
    /// Fits the widest reset text, a countdown with a weekday and time (about 100pt at 10pt with
    /// monospaced digits).
    static let resetWidth: CGFloat = 102
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
                resetsAt: window.resetsAt,
                warningWindow: Self.warningWindow(
                    window,
                    provider: self.provider,
                    infersPeriodFromReset: self.infersPeriodFromReset))
        }
    }

    /// A window of a day or less follows the session thresholds; everything longer, including a window
    /// whose length is unknown, follows the weekly ones.
    static func warningWindow(
        _ window: RateWindow,
        provider: UsageProvider?,
        infersPeriodFromReset: Bool = true) -> QuotaWarningWindow
    {
        let minutes = self.nativeMinutes(window, provider: provider, infersPeriodFromReset: infersPeriodFromReset)
        return (minutes ?? .max) <= 1440 ? .session : .weekly
    }

    var updatedText: String? {
        self.updatedAt.map { L("Updated %@", Self.age(of: $0, now: self.now)) }
    }

    /// Time since `date`, in the same compact form as the reset countdowns ("3m", "1d 2h").
    private static func age(of date: Date, now: Date) -> String {
        self.countdown(to: now, now: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            self.header
            if let errorText {
                Text(errorText)
                    .font(.system(size: 10))
                    .foregroundStyle(MenuHighlightStyle.error(self.isHighlighted))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                self.windowLines
            }
        }
        .padding(.horizontal, Self.contentInset)
        .padding(.vertical, Self.verticalPadding)
        .frame(width: self.width, alignment: .leading)
        .overlay(alignment: .bottom) {
            if self.showsDivider {
                Rectangle()
                    .fill(Self.dividerColor)
                    .frame(height: 0.5)
                    .padding(.horizontal, Self.contentInset)
            }
        }
    }

    static let dividerColor = Color.white.opacity(0.08)

    var resetCreditsText: String? {
        guard let resetCredits else { return nil }
        let expiry = resetCredits.nextExpiry.map { " · \(Self.countdown(to: $0, now: self.now))" } ?? ""
        return "\(resetCredits.count)\(expiry)"
    }

    var scheduledResetText: String? {
        self.scheduledResetAt.map { Self.countdown(to: $0, now: self.now) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                if self.namesProvider {
                    OverviewProviderIcon(image: self.icon, isTemplate: self.iconIsTemplate)
                        .scaleEffect(14.0 / 18)
                        .frame(width: 14, height: 14)
                }
                // An error-only card keeps its name white: the red message carries the error on its own.
                Text(self.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(self.errorText == nil ? self.nameColor : .white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let providerTag {
                    Text(providerTag)
                        .font(.system(size: 11))
                        .foregroundStyle(OverviewPalette.faint)
                        .lineLimit(1)
                }
                if let plan {
                    Text(plan)
                        .font(.system(size: 10))
                        .foregroundStyle(OverviewPalette.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.07)))
                }
            }
            if let resetCreditsText {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.counterclockwise")
                    Text(resetCreditsText)
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(OverviewPalette.caption)
                .fixedSize()
            }
            if let scheduledResetText {
                HStack(spacing: 3) {
                    Image(systemName: "clock")
                    Text(scheduledResetText)
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(OverviewPalette.caption)
                .fixedSize()
            }
            Spacer(minLength: 4)
            if let updatedText {
                Text(updatedText)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(OverviewPalette.caption)
                    .fixedSize()
            }
        }
    }

    private var nameColor: Color {
        if self.showsErrorFlag { return OverviewPalette.warning }
        return self.namesProvider ? .white : Color.white.opacity(0.85)
    }

    @ViewBuilder
    private var windowLines: some View {
        let lines = self.lines
        VStack(alignment: .leading, spacing: 0) {
            ForEach(lines.indices, id: \.self) { index in
                self.windowLine { self.readingView(lines[index]) }
            }
        }
        .opacity(self.isStale ? 0.5 : 1)
    }

    private func windowLine(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(height: Self.lineHeight)
    }

    /// What one line draws. Severity and pace read the used percentage, so `showsRemaining` moves
    /// only `percent` (and the bar's fill); every colour stays where the used reading puts it.
    struct Reading: Equatable {
        let percent: Double
        let barColor: Color
        let percentColor: Color
        /// Pace tick position, nil without a pace or with pace hidden.
        let pacePercent: Double?
        /// Usage is ahead of the pace tick, so the stretch between the two is hatched.
        let overruns: Bool
    }

    func reading(for line: Line) -> Reading {
        let thresholds = self.display.warningThresholds(for: line.warningWindow)
        return Reading(
            percent: Self.displayedPercent(line.used, showsRemaining: self.display.showsRemaining),
            barColor: OverviewPalette.color(usedPercent: line.used, warningThresholds: thresholds),
            percentColor: OverviewPalette.percentColor(usedPercent: line.used, warningThresholds: thresholds),
            pacePercent: self.display.showsPace
                ? line.pacePercent.map { Self.displayedPercent($0, showsRemaining: self.display.showsRemaining) }
                : nil,
            overruns: self.display.showsPace && line.pacePercent.map { line.used > $0 } == true)
    }

    private func readingView(_ line: Line) -> some View {
        let reading = self.reading(for: line)
        return HStack(spacing: Self.columnSpacing) {
            Text(line.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(OverviewPalette.caption)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)
            UsageBar(
                used: reading.percent,
                color: reading.barColor,
                trackColor: Self.trackColor,
                height: Self.barHeight,
                pacePercent: reading.pacePercent,
                overruns: reading.overruns)
            Text("\(Int(reading.percent.rounded()))%")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(reading.percentColor)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: Self.percentWidth, alignment: .trailing)
            Text(Self.resetText(line, now: self.now))
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(OverviewPalette.reset)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: Self.resetWidth, alignment: .leading)
        }
    }

    static func displayedPercent(_ used: Double, showsRemaining: Bool) -> Double {
        showsRemaining ? 100 - used : used
    }

    static let barHeight: CGFloat = 4
    /// The gap between a line's label, bar, percent and reset columns.
    static let columnSpacing: CGFloat = 8

    /// Menus are pinned dark, so the empty part of a bar is drawn light enough to read there.
    static let trackColor = Color.white.opacity(0.10)

    /// Explicit durations determine the slots. Untyped readings use only provider-owned semantics;
    /// an unknown reading occupies the long slot first and keeps a duration-free label. A window whose
    /// usage item the user hid takes no slot, exactly as a hidden magpie window takes no line.
    static func slots(
        of snapshot: UsageSnapshot?,
        provider: UsageProvider? = nil,
        hiddenItemIDs: Set<ProviderUsageItemID> = []) -> (short: RateWindow?, long: RateWindow?)
    {
        guard let snapshot else { return (nil, nil) }
        let infersPeriod = !snapshot.isMagpieSourced
        let windows = Self.visibleLanes(of: snapshot, hiddenItemIDs: hiddenItemIDs)
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

    /// The quota lanes whose usage item the user has not hidden.
    static func visibleLanes(of snapshot: UsageSnapshot?, hiddenItemIDs: Set<ProviderUsageItemID>) -> [RateWindow] {
        self.reportedLanes(of: snapshot).compactMap { lane in
            hiddenItemIDs.contains(.metric(lane.id)) ? nil : lane.window
        }
    }

    /// The snapshot's three quota lanes under the ids their usage items carry in Settings.
    static func reportedLanes(of snapshot: UsageSnapshot?) -> [(id: String, window: RateWindow)] {
        guard let snapshot else { return [] }
        return [("primary", snapshot.primary), ("secondary", snapshot.secondary), ("tertiary", snapshot.tertiary)]
            .compactMap { id, window in window.map { (id: id, window: $0) } }
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
        if minutes >= 28 * 1440 { return "30d" }
        if minutes >= 1440 { return "\(minutes / 1440)d" }
        return "\(max(1, minutes / 60))h"
    }

    /// A placeholder window stands for a lane the provider did not report, so it gets no number.
    static func used(_ window: RateWindow?) -> Double? {
        guard let window, !window.isSyntheticPlaceholder else { return nil }
        return min(100, max(0, window.usedPercent))
    }

    static func resetText(_ line: Line, now: Date) -> String {
        guard let date = line.resetsAt else { return "—" }
        return "\(self.countdown(to: date, now: now)) · \(self.shortClock(date, now: now))"
    }

    /// A short form of the detail page's clock: today "14:30", within the next six days "Thu 03:00",
    /// and beyond that "Oct 28". The countdown beside it settles which week a weekday falls in.
    static func shortClock(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = calendar.timeZone
        clock.dateFormat = "HH:mm"
        let time = clock.string(from: date)
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: date)).day ?? 0
        if days == 0 { return time }
        let style = Date.FormatStyle(
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: calendar,
            timeZone: calendar.timeZone)
        if days >= 1, days < 7 {
            return "\(date.formatted(style.weekday(.abbreviated))) \(time)"
        }
        return date.formatted(style.month(.abbreviated).day())
    }

    static func countdown(to date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let days = minutes / 1440, hours = (minutes % 1440) / 60, mins = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
}

/// A rounded track with its fill drawn as a rectangle clipped to the track, so a small reading keeps
/// the track's rounded left end instead of collapsing into a sliver. Any reading above 0% is at least
/// as wide as the bar is tall, so it shows as a coloured dot; 0% shows no fill.
struct UsageBar: View {
    let used: Double
    let color: Color
    let trackColor: Color
    let height: CGFloat
    /// Where the linear pace says usage should be by now; drawn as a white tick that stands out of the bar.
    var pacePercent: Double?
    /// Hatches the stretch between the fill's end and the pace tick, the usage that is ahead of the pace.
    var overruns = false

    /// The stretch between the fill's end and the pace tick, in percent of the bar; nil when they coincide.
    var overrunSegment: (start: Double, end: Double)? {
        guard self.overruns, let pacePercent else { return nil }
        let fillEnd = min(100, max(0, self.used))
        let tick = min(100, max(0, pacePercent))
        guard abs(fillEnd - tick) >= 1 else { return nil }
        return (min(fillEnd, tick), max(fillEnd, tick))
    }

    /// The fill reaches the pace tick, so the hatched stretch lies on the fill; when the fill ends short of the
    /// tick (a remaining display) it lies on the track.
    var overrunIsInsideFill: Bool {
        self.used >= (self.pacePercent ?? 0)
    }

    private static let tickOverhang: CGFloat = 2

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(self.trackColor)
                    Rectangle()
                        .fill(self.color)
                        .frame(width: Self.fillWidth(used: self.used, barWidth: proxy.size.width, height: self.height))
                    if let segment = self.overrunSegment {
                        // Inside the fill the stripes darken it; past the fill's end (remaining display) the
                        // gap is stripes of the tone on the bare track, so it does not read as fill.
                        Rectangle()
                            .fill(self.overrunIsInsideFill ? self.color : Color.clear)
                            .frame(width: proxy.size.width * (segment.end - segment.start) / 100)
                            .overlay(Self.hatching(
                                stripe: self.overrunIsInsideFill ? .black.opacity(0.35) : self.color.opacity(0.45)))
                            .offset(x: proxy.size.width * segment.start / 100)
                    }
                }
                .frame(height: self.height)
                .clipShape(RoundedRectangle(cornerRadius: self.height / 2))
                if let pacePercent {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white)
                        .frame(width: 2, height: self.height + 2 * Self.tickOverhang)
                        .overlay(
                            RoundedRectangle(cornerRadius: 1.5)
                                .stroke(Color(nsColor: OverviewPalette.panelBase).opacity(0.9), lineWidth: 1)
                                .padding(-1))
                        .offset(x: proxy.size.width * min(100, max(0, pacePercent)) / 100 - 1)
                }
            }
            .frame(height: proxy.size.height)
        }
        .frame(height: self.height + 2 * Self.tickOverhang)
    }

    private static func hatching(stripe: Color) -> some View {
        Canvas { context, size in
            var path = Path()
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 4
            }
            context.stroke(path, with: .color(stripe), lineWidth: 2)
        }
    }

    static func fillWidth(used: Double, barWidth: CGFloat, height: CGFloat) -> CGFloat {
        guard used > 0 else { return 0 }
        let width = barWidth * min(1, used / 100)
        return min(barWidth, max(height, width))
    }
}
