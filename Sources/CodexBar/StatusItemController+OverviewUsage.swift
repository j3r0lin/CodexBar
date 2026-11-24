import AppKit
import CodexBarCore
import SwiftUI

/// The Overview's usage card: today's spend as the headline beside the gateway's whole window,
/// each side carrying the same three facts so the two read against each other.
struct OverviewUsageCardModel {
    struct Side: Equatable {
        let labelText: String
        let spendText: String
        /// The token count, drawn brighter than the rest of its line, e.g. "101M".
        let tokenCountText: String
        /// The rest of the line after the count, e.g. "tokens · 96% cached".
        let detailText: String
    }

    /// Not drawn: the two sides' labels say what the numbers are. VoiceOver still opens with it.
    let titleText: String
    let today: Side
    let period: Side

    init(summary: MagpieUsageSummary, now: Date = Date(), calendar: Calendar = .current) {
        self.titleText = L("Usage & Spend")
        self.today = Self.side(L("Today"), summary.totals(onDayOf: now, calendar: calendar))
        self.period = Self.side(spendDashboardDayRangeText(summary.periodDays), summary.total)
    }

    private static func side(_ label: String, _ totals: MagpieUsageTotals) -> Side {
        let cache = totals.cacheHitRate.map {
            L("%@ cached", "\(Int(($0 * 100).rounded()))%")
        }
        return Side(
            labelText: label,
            spendText: UsageFormatter.currencyString(totals.cost, currencyCode: "USD"),
            tokenCountText: ShareStatsFormatting.compactCount(totals.tokenCount),
            detailText: [L("tokens"), cache].compactMap(\.self).joined(separator: " · "))
    }

    /// Every value that can change the card's height, hashed by the shared helper so the cache is
    /// keyed on shape rather than on the text itself.
    var heightFingerprint: String {
        MenuCardHeightFingerprint.join([
            MenuCardHeightFingerprint.field("title", self.titleText),
            MenuCardHeightFingerprint.field("todayLabel", self.today.labelText),
            MenuCardHeightFingerprint.field("todaySpend", self.today.spendText),
            MenuCardHeightFingerprint.field("todayTokens", self.today.tokenCountText),
            MenuCardHeightFingerprint.field("todayDetail", self.today.detailText),
            MenuCardHeightFingerprint.field("periodLabel", self.period.labelText),
            MenuCardHeightFingerprint.field("periodSpend", self.period.spendText),
            MenuCardHeightFingerprint.field("periodTokens", self.period.tokenCountText),
            MenuCardHeightFingerprint.field("periodDetail", self.period.detailText),
        ])
    }

    var accessibilityText: String {
        [
            self.titleText,
            Self.spoken(self.today),
            Self.spoken(self.period),
        ].joined(separator: ", ")
    }

    private static func spoken(_ side: Side) -> String {
        "\(side.labelText) \(side.spendText), \(side.tokenCountText) \(side.detailText)"
    }
}

struct OverviewUsageCardView: View {
    let model: OverviewUsageCardModel
    let width: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            self.sideView(self.model.today, spendSize: 28, alignment: .leading)
            Spacer(minLength: 0)
            self.sideView(self.model.period, spendSize: 20, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0x26 / 255, green: 0x2A / 255, blue: 0x33 / 255),
                        Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x26 / 255),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing)))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.5))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .frame(width: self.width, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.model.accessibilityText)
    }

    private func sideView(
        _ side: OverviewUsageCardModel.Side,
        spendSize: CGFloat,
        alignment: HorizontalAlignment) -> some View
    {
        VStack(alignment: alignment, spacing: 3) {
            Text(side.labelText)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(1)
            Text(side.spendText)
                .font(.system(size: spendSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            (Text(side.tokenCountText)
                .fontWeight(.semibold)
                .foregroundColor(Color.white.opacity(0.58))
                + Text(" \(side.detailText)"))
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.38))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}
