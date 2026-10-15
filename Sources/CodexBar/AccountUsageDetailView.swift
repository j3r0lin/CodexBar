import AppKit
import CodexBarCore
import SwiftUI

/// Usage detail of one account or provider, shown in the Overview row's detail submenu: a header with the
/// provider icon, then one block per window the provider reported, each with its name, a bar, the used
/// percentage and the absolute reset time.
struct AccountUsageDetailView: View {
    static let defaultWidth: CGFloat = 240

    let provider: UsageProvider?
    let providerName: String
    /// Set on a magpie account row, which shows one account of the provider.
    var accountName: String?
    let snapshot: UsageSnapshot?
    var width: CGFloat = Self.defaultWidth
    var now = Date()

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

    private func blockView(_ block: Block) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(block.title)
                .font(.system(size: 13))
            UsageBar(
                used: block.used,
                color: Color(nsColor: UsageSeverityPalette.color(usedPercent: block.used)),
                trackColor: Color.white.opacity(0.16),
                height: 6)
            HStack(alignment: .firstTextBaseline) {
                Text(Self.usedText(block.used))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                Spacer(minLength: 8)
                if let resetsAt = block.window.resetsAt {
                    Text(Self.resetText(resetsAt))
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
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

    static func usedText(_ used: Double) -> String {
        L("account_detail_used", "\(Int(used.rounded()))%")
    }

    static func resetText(_ date: Date) -> String {
        let style = Date.FormatStyle(locale: codexBarLocalizedResourceLocale())
            .month(.abbreviated).day().hour().minute()
        return L("Resets %@", date.formatted(style))
    }
}
