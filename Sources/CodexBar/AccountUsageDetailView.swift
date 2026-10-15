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
    var now = Date()
    static let historyDays = 30

    struct Block: Equatable {
        let title: String
        let window: RateWindow
        let used: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            self.header
            let blocks = Self.blocks(of: self.snapshot)
            if blocks.isEmpty {
                Text(L("No data"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(blocks.indices, id: \.self) { index in
                    self.blockView(blocks[index])
                }
            }
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

    private func blockView(_ block: Block) -> some View {
        let color = OverviewPalette.color(usedPercent: block.used)
        return VStack(alignment: .leading, spacing: 6) {
            self.sectionHeader(block.title, trailing: block.window.resetsAt.map(Self.resetText))
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

    /// Every window with a real reading, in the provider's order, followed by its named extra windows.
    static func blocks(of snapshot: UsageSnapshot?) -> [Block] {
        guard let snapshot else { return [] }
        let lanes = [snapshot.primary, snapshot.secondary, snapshot.tertiary].compactMap { window -> Block? in
            guard let window, let used = OverviewCompactAccountRow.used(window) else { return nil }
            return Block(title: Self.windowTitle(window), window: window, used: used)
        }
        let extras = (snapshot.extraRateWindows ?? []).compactMap { named -> Block? in
            guard named.usageKnown, let used = OverviewCompactAccountRow.used(named.window) else { return nil }
            return Block(title: named.title, window: named.window, used: used)
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
