import AppKit
import CodexBarCore
import SwiftUI

/// Usage detail of one account or provider, shown in the Overview row's detail submenu: a header with the
/// provider icon, then one block per window the provider reported, each with its name, a bar, the used
/// percentage and the absolute reset time, and a 30-day history of the provider's longest window when one
/// was recorded.
struct AccountUsageDetailView: View {
    static let defaultWidth: CGFloat = 240

    let provider: UsageProvider?
    let providerName: String
    /// Set on a magpie account row, which shows one account of the provider.
    var accountName: String?
    let snapshot: UsageSnapshot?
    var width: CGFloat = Self.defaultWidth
    /// Daily peaks, oldest first; nil marks a day without a sample. Empty hides the history.
    var history: [Double?] = []
    /// The caller's menu-card model, already filtered by the user's hidden usage items.
    var model: UsageMenuCardView.Model?
    var now = Date()
    static let historyDays = 30

    struct Block: Equatable {
        let title: String
        let window: RateWindow
        let used: Double
        /// Absolute reset time when the raw window has one, else the menu card's own reset text.
        var resetText: String?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            self.header
            let blocks = Self.blocks(of: self.snapshot, model: self.model)
            if blocks.isEmpty, !self.hasSupplementalContent {
                Text(L("No data"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(blocks.indices, id: \.self) { index in
                    self.blockView(blocks[index])
                }
            }
            self.supplementalView
            if self.history.contains(where: { $0 != nil }) {
                self.historyView
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: self.width, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Self.icon(for: self.provider)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .foregroundStyle(.primary)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
            Text(L("account_detail_usage_title", self.providerName))
                .font(.system(size: 17, weight: .bold))
                .lineLimit(1)
                .fixedSize()
            if let accountName {
                Text(accountName)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).overviewSectionTitleStyle().lineLimit(1)
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
        let color = OverviewPalette.color(usedPercent: block.used)
        return VStack(alignment: .leading, spacing: 6) {
            self.sectionHeader(block.title, trailing: block.resetText)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int(block.used.rounded()))%")
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .foregroundStyle(color)
                Text(L("used"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            UsageBar(used: block.used, color: color, trackColor: OverviewCompactAccountRow.trackColor, height: 6)
        }
    }

    /// Thin bars without axes or grid: the history is there for its trend, not for reading values.
    private var historyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            self.sectionHeader(L("account_detail_history"), trailing: L("Last %d days", Self.historyDays))
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 1) {
                    ForEach(self.history.indices, id: \.self) { index in
                        UnevenRoundedRectangle(topLeadingRadius: 1, topTrailingRadius: 1)
                            .fill(OverviewPalette.accent)
                            .frame(height: proxy.size.height * min(1, max(0, (self.history[index] ?? 0) / 100)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
            }
            .frame(height: 40)
        }
    }

    /// One value per day for the last `days` days, oldest first: the highest reading of the longest
    /// recorded window on that day, or nil when the day has no sample. Empty when nothing was recorded.
    static func dailyPeaks(
        _ histories: [PlanUtilizationSeriesHistory],
        now: Date,
        days: Int = Self.historyDays,
        calendar: Calendar = .current) -> [Double?]
    {
        guard let series = histories.filter({ !$0.entries.isEmpty }).max(by: { $0.windowMinutes < $1.windowMinutes })
        else { return [] }
        let today = calendar.startOfDay(for: now)
        var peaks = [Double?](repeating: nil, count: days)
        for entry in series.entries {
            let day = calendar.startOfDay(for: entry.capturedAt)
            guard let offset = calendar.dateComponents([.day], from: day, to: today).day,
                  (0..<days).contains(offset)
            else { continue }
            let index = days - 1 - offset
            peaks[index] = max(peaks[index] ?? 0, min(100, max(0, entry.usedPercent)))
        }
        return peaks.contains(where: { $0 != nil }) ? peaks : []
    }

    private static func icon(for provider: UsageProvider?) -> Image {
        if let provider, let image = ProviderBrandIcon.image(for: provider) {
            return Image(nsImage: image)
        }
        return Image(systemName: "gauge.with.dots.needle.33percent")
    }

    /// Every window with a real reading. Without a model that is the snapshot's own windows; with one it is
    /// the model's metrics, which already carry the user's hidden items and optional-usage gates and cover
    /// lanes the raw snapshot lacks (Codex monthly credits). A metric that matches a raw window keeps the
    /// window's absolute reset date.
    static func blocks(of snapshot: UsageSnapshot?, model: UsageMenuCardView.Model? = nil) -> [Block] {
        guard let model else { return self.snapshotBlocks(of: snapshot) }
        let raw = Self.snapshotBlocks(of: snapshot)
        return model.metrics.compactMap { metric -> Block? in
            guard metric.statusText == nil else { return nil }
            let used = metric.percentStyle == .used ? metric.percent : 100 - metric.percent
            if let window = Self.rawWindow(id: metric.id, in: snapshot),
               let block = raw.first(where: { $0.window == window })
            {
                return Block(title: metric.title, window: window, used: block.used, resetText: block.resetText)
            }
            let window = RateWindow(usedPercent: used, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
            return Block(title: metric.title, window: window, used: used, resetText: metric.resetText)
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

    /// Every window with a real reading, in the provider's order, followed by its named extra windows.
    private static func snapshotBlocks(of snapshot: UsageSnapshot?) -> [Block] {
        guard let snapshot else { return [] }
        let lanes = [snapshot.primary, snapshot.secondary, snapshot.tertiary].compactMap { window -> Block? in
            guard let window, let used = OverviewCompactAccountRow.used(window) else { return nil }
            return Block(
                title: Self.windowTitle(window),
                window: window,
                used: used,
                resetText: window.resetsAt.map(Self.resetText))
        }
        let extras = (snapshot.extraRateWindows ?? []).compactMap { named -> Block? in
            guard named.usageKnown, let used = OverviewCompactAccountRow.used(named.window) else { return nil }
            return Block(
                title: named.title,
                window: named.window,
                used: used,
                resetText: named.window.resetsAt.map(Self.resetText))
        }
        return lanes + extras
    }

    static func windowTitle(_ window: RateWindow) -> String {
        guard let minutes = window.windowMinutes else { return L("Window") }
        if minutes == 5 * 60 { return L("5-hour limit") }
        if minutes == 7 * 1440 { return L("Weekly limit") }
        if minutes % 1440 == 0 { return L("account_detail_window_days", minutes / 1440) }
        if minutes % 60 == 0 { return L("account_detail_window_hours", minutes / 60) }
        return L("account_detail_window_minutes", minutes)
    }

    static func resetText(_ date: Date) -> String {
        let style = Date.FormatStyle(locale: codexBarLocalizedResourceLocale())
            .month(.abbreviated).day().hour().minute()
        return L("Resets %@", date.formatted(style))
    }
}
