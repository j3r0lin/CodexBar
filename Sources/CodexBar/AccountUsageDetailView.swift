import AppKit
import CodexBarCore
import SwiftUI

/// Usage detail of one account or provider, shown in the Overview row's detail submenu: the account's name
/// and when it was read, then one block per window the provider reported with its used percentage, its
/// reset time, where its pace is heading and, for magpie accounts with readings, its current cycle's curve.
struct AccountUsageDetailView: View {
    static let defaultWidth: CGFloat = 240
    static let curveHeight: CGFloat = 30

    let provider: UsageProvider?
    let providerName: String
    /// Set on a magpie account row, which shows one account of the provider.
    var accountName: String?
    /// Magpie rows: the account's plan, shown after the name.
    var plan: String?
    let snapshot: UsageSnapshot?
    /// Magpie rows pass every window the gateway reported, each under its own name (Month,
    /// model-scoped weekly, unknown wire names included), instead of the snapshot's lanes.
    var namedWindows: [OverviewUsageRow.NamedWindow]?
    /// The account's error. Without windows it replaces them; beside retained windows it explains them.
    var errorText: String?
    var width: CGFloat = Self.defaultWidth
    /// The caller's menu-card model, already filtered by the user's hidden usage items.
    var model: UsageMenuCardView.Model?
    var now = Date()
    /// Magpie rows: when the gateway last read the account. Native rows use the snapshot's time.
    var readAt: Date?
    var display = OverviewDisplayOptions()
    /// Native rows: usage items the user hid, which the snapshot's own lanes must honour as the card does.
    var hiddenItemIDs: Set<ProviderUsageItemID> = []
    /// The reading is older than the refresh cadence allows; its numbers are dimmed as on the row.
    var isStale = false
    /// Magpie rows: the account's reset credits, one entry each with its expiry.
    var resetCredits: MagpieResetCredits?
    var resetStyle: ResetTimeDisplayStyle = .countdown

    struct Block: Equatable {
        var title: String
        let window: RateWindow
        let used: Double
        /// Which warning thresholds colour this block; a window of unknown length follows weekly.
        var warningWindow: QuotaWarningWindow = .weekly
        /// "Resets <clock>" when the raw window has a reset time, else the menu card's own reset text.
        var resetText: String?
        var outlook: OverviewUsageRow.PaceOutlook?
        /// Magpie windows with readings of their current cycle; nil draws no curve.
        var trend: OverviewUsageRow.Trend?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            self.header
            if let errorText, self.namedWindows?.isEmpty == true {
                self.errorView(errorText)
            } else {
                let blocks = self.namedWindows.map { Self.blocks(of: $0, now: self.now) }
                    ?? Self.blocks(
                        of: self.snapshot,
                        provider: self.provider,
                        model: self.model,
                        hiddenItemIDs: self.hiddenItemIDs,
                        infersPeriodFromReset: self.namedWindows == nil,
                        now: self.now)
                if blocks.isEmpty, !self.hasSupplementalContent, self.resetCreditsPresentation == nil,
                   self.errorText == nil
                {
                    Text(L("No data"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(blocks.indices, id: \.self) { index in
                        self.blockView(blocks[index])
                    }
                    .opacity(self.isStale ? 0.5 : 1)
                }
                self.supplementalView
                if let resetCreditsPresentation = self.resetCreditsPresentation {
                    LimitResetCreditsContent(presentation: resetCreditsPresentation)
                }
                if let errorText {
                    self.errorView(errorText)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: self.width, alignment: .leading)
    }

    var resetCreditsPresentation: LimitResetCreditsPresentation? {
        self.resetCredits.flatMap {
            LimitResetCreditsPresentation.make(expirations: $0.expirations, resetStyle: self.resetStyle, now: self.now)
        }
    }

    private var updatedAt: Date? {
        self.readAt ?? self.snapshot?.updatedAt
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Self.icon(for: self.provider)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(.primary)
            Text(self.accountName ?? self.providerName)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .truncationMode(.middle)
            if let plan {
                // Plans are short ("team", "GLM Coding Lite"); a long account name gives way instead.
                Text(plan)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 8)
            if let updatedAt {
                Text(L("Updated %@", Self.clockText(updatedAt, now: self.now)))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    private func errorView(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(OverviewPalette.warning)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            // Not upper-cased: magpie windows use the row's short labels ("5h", "7d"), which read wrong as "5H".
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OverviewPalette.accent)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// The already-curated menu model supplies provider details, credits, notes and the failure state.
    /// The detail filters nothing itself, so hidden-item settings and optional-usage gates stay shared.
    @ViewBuilder
    private var supplementalView: some View {
        if let model = self.model {
            if model.subtitleStyle == .error, !model.subtitleText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    self.sectionHeader(L("Error"), trailing: nil)
                    self.noteText(model.subtitleText)
                }
            }
            if let lastKnownUsageText = model.lastKnownUsageText {
                self.noteText(lastKnownUsageText)
            }
            if let creditsText = model.creditsText, !creditsText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    self.sectionHeader(L("Credits"), trailing: nil)
                    Text(creditsText)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
            }
            ForEach(model.providerDetails.indices, id: \.self) { index in
                let section = model.providerDetails[index]
                VStack(alignment: .leading, spacing: 6) {
                    if let title = section.title {
                        self.sectionHeader(title, trailing: nil)
                    }
                    ForEach(section.rows.indices, id: \.self) { rowIndex in
                        self.detailRow(section.rows[rowIndex])
                    }
                }
            }
            ForEach(model.usageNotes.indices, id: \.self) { index in
                self.noteText(model.usageNotes[index])
            }
        }
    }

    /// "No data" only stands in when the card has no usage windows and nothing else to say.
    private var hasSupplementalContent: Bool {
        guard let model else { return false }
        return !model.providerDetails.isEmpty || !(model.creditsText ?? "").isEmpty
            || !model.usageNotes.isEmpty || model.subtitleStyle == .error
    }

    private func noteText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func detailRow(_ row: ProviderDetailSection.Row) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(row.label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(row.value)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            if let secondary = row.secondaryValue, !secondary.isEmpty {
                Text(secondary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func blockView(_ block: Block) -> some View {
        let color = OverviewPalette.color(
            usedPercent: block.used,
            warningThresholds: self.display.warningThresholds(for: block.warningWindow))
        let percent = OverviewCompactAccountRow.displayedPercent(
            block.used,
            showsRemaining: self.display.showsRemaining)
        return VStack(alignment: .leading, spacing: 6) {
            self.sectionHeader(block.title, trailing: block.resetText)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int(percent.rounded()))%")
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                Text(self.display.showsRemaining ? L("usage_percent_suffix_left") : L("used"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if self.display.showsPace, let outlook = block.outlook {
                    Text(Self.paceText(outlook, now: self.now))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Self.paceColor(outlook))
                        .lineLimit(1)
                }
            }
            if self.display.showsPace, let trend = block.trend, trend.current.count >= 2 {
                QuotaCycleCurve(trend: trend, now: self.now)
                    .frame(height: Self.curveHeight)
            }
        }
    }

    static func paceText(_ outlook: OverviewUsageRow.PaceOutlook, now: Date) -> String {
        switch outlook {
        case let .runsOut(date):
            L("Runs out %@ at this pace", Self.clockText(max(date, now.addingTimeInterval(60)), now: now))
        case .lastsPastReset:
            L("Lasts past the reset at this pace")
        }
    }

    private static func paceColor(_ outlook: OverviewUsageRow.PaceOutlook) -> Color {
        switch outlook {
        case .runsOut: OverviewPalette.critical
        case .lastsPastReset: Color.secondary
        }
    }

    private static func icon(for provider: UsageProvider?) -> Image {
        // Unknown magpie providers have no brand icon and no native descriptor.
        guard let provider else { return Image(systemName: "network") }
        if let image = ProviderBrandIcon.image(for: provider) {
            return Image(nsImage: image)
        }
        return Image(systemName: "gauge.with.dots.needle.33percent")
    }

    /// Every window with a real reading. Without a model that is the snapshot's own windows; with one it is
    /// the model's metrics, which already carry the user's hidden items and optional-usage gates and cover
    /// lanes the raw snapshot lacks (Codex monthly credits). A metric that matches a raw window keeps the
    /// window's reset time and pace.
    static func blocks(
        of snapshot: UsageSnapshot?,
        provider: UsageProvider? = nil,
        model: UsageMenuCardView.Model? = nil,
        hiddenItemIDs: Set<ProviderUsageItemID> = [],
        infersPeriodFromReset: Bool = true,
        now: Date = Date()) -> [Block]
    {
        let raw = Self.snapshotBlocks(
            of: snapshot,
            provider: provider,
            hiddenItemIDs: hiddenItemIDs,
            infersPeriodFromReset: infersPeriodFromReset,
            now: now)
        guard let model else { return raw }
        return model.metrics.compactMap { metric -> Block? in
            guard metric.statusText == nil else { return nil }
            let used = metric.percentStyle == .used ? metric.percent : 100 - metric.percent
            if let window = Self.rawWindow(id: metric.id, in: snapshot),
               var block = raw.first(where: { $0.window == window })
            {
                block.title = metric.title
                return block
            }
            let window = RateWindow(usedPercent: used, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
            return Block(
                title: metric.title,
                window: window,
                used: used,
                resetText: metric.resetText)
        }
    }

    private static func rawWindow(id: String, in snapshot: UsageSnapshot?) -> RateWindow? {
        switch id {
        case "primary": snapshot?.primary
        case "secondary": snapshot?.secondary
        case "tertiary": snapshot?.tertiary
        default: snapshot?.extraRateWindows?.first { $0.id == id }?.window
        }
    }

    /// One block per window a magpie account reported, each under its own name, with the pace fitted to
    /// its readings when magpie kept enough of them.
    static func blocks(of named: [OverviewUsageRow.NamedWindow], now: Date = Date()) -> [Block] {
        named.map { window in
            Block(
                title: window.label,
                window: RateWindow(
                    usedPercent: window.used,
                    windowMinutes: nil,
                    resetsAt: window.resetsAt,
                    resetDescription: nil),
                used: window.used,
                warningWindow: OverviewUsageRow.warningWindow(for: window),
                resetText: window.resetsAt.map { Self.resetText($0, now: now) },
                outlook: window.outlook(now: now),
                trend: window.trend(now: now))
        }
    }

    /// Every window with a real reading, in the provider's order, followed by its named extra windows.
    private static func snapshotBlocks(
        of snapshot: UsageSnapshot?,
        provider: UsageProvider?,
        hiddenItemIDs: Set<ProviderUsageItemID>,
        infersPeriodFromReset: Bool,
        now: Date) -> [Block]
    {
        guard let snapshot else { return [] }
        let lanes = OverviewCompactAccountRow.visibleLanes(of: snapshot, hiddenItemIDs: hiddenItemIDs)
            .compactMap { window -> Block? in
                Self.nativeBlock(
                    title: Self.windowTitle(window),
                    window: window,
                    provider: provider,
                    infersPeriodFromReset: infersPeriodFromReset,
                    now: now)
            }
        let extras = (snapshot.extraRateWindows ?? []).compactMap { named -> Block? in
            guard named.usageKnown else { return nil }
            return Self.nativeBlock(
                title: named.title,
                window: named.window,
                provider: provider,
                infersPeriodFromReset: infersPeriodFromReset,
                now: now)
        }
        return lanes + extras
    }

    private static func nativeBlock(
        title: String,
        window: RateWindow,
        provider: UsageProvider?,
        infersPeriodFromReset: Bool,
        now: Date) -> Block?
    {
        guard let used = OverviewCompactAccountRow.used(window) else { return nil }
        let pace = OverviewUsageRow.linearPace(
            used: used,
            duration: window.windowMinutes.map { TimeInterval($0) * 60 },
            resetsAt: window.resetsAt,
            now: now)
        return Block(
            title: title,
            window: window,
            used: used,
            warningWindow: OverviewCompactAccountRow.warningWindow(
                window,
                provider: provider,
                infersPeriodFromReset: infersPeriodFromReset),
            resetText: window.resetsAt.map { Self.resetText($0, now: now) },
            outlook: pace.flatMap { OverviewUsageRow.PaceOutlook(pace: $0, now: now) })
    }

    static func windowTitle(_ window: RateWindow) -> String {
        guard let minutes = window.windowMinutes else { return L("Window") }
        if minutes == 5 * 60 { return L("5-hour limit") }
        if minutes == 7 * 1440 { return L("Weekly limit") }
        if minutes % 1440 == 0 { return L("account_detail_window_days", minutes / 1440) }
        if minutes % 60 == 0 { return L("account_detail_window_hours", minutes / 60) }
        return L("account_detail_window_minutes", minutes)
    }

    static func resetText(_ date: Date, now: Date) -> String {
        L("Resets %@", self.clockText(date, now: now))
    }

    /// A time on the 24-hour clock, as magpie's tray writes reset times: "14:30" today, "Thu 14:30" later
    /// this week (Monday to Sunday), else "Oct 12 08:05". Earlier days get the date too,
    /// so an old "Updated" time never reads as today's.
    static func clockText(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let locale = codexBarLocalizedResourceLocale()
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
        // Days left in this Monday-to-Sunday week; Calendar numbers Sunday 1 through Saturday 7.
        let daysLeftInWeek = 6 - (calendar.component(.weekday, from: now) + 5) % 7
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        if days >= 1, days <= daysLeftInWeek {
            style = style.weekday(.abbreviated)
        } else {
            style = style.month(.abbreviated).day()
        }
        return "\(date.formatted(style)) \(time)"
    }
}
