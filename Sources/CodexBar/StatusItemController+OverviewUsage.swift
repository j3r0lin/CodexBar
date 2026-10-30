import AppKit
import CodexBarCore
import SwiftUI

/// The Overview's usage card: the gateway's 30-day spend as the headline, with today's spend, tokens,
/// and calls as three right-aligned facts.
struct OverviewUsageCardModel: Equatable {
    let titleText: String
    let totalSpendText: String
    let todaySpendText: String
    let tokenText: String
    let callText: String

    init(summary: MagpieUsageSummary, now: Date = Date(), calendar: Calendar = .current) {
        self.titleText = "\(L("Usage & Spend")) · \(spendDashboardDayRangeText(summary.periodDays))"
        self.totalSpendText = UsageFormatter.currencyString(summary.totalCost, currencyCode: "USD")
        self.todaySpendText = UsageFormatter.currencyString(
            summary.cost(onSameDayAs: now, calendar: calendar),
            currencyCode: "USD")
        self.tokenText = ShareStatsFormatting.compactCount(summary.tokenCount)
        self.callText = ShareStatsFormatting.compactCount(summary.calls)
    }

    /// Every value that can change the card's height.
    var heightFingerprint: String {
        [
            self.titleText,
            self.totalSpendText,
            self.todaySpendText,
            self.tokenText,
            self.callText,
        ].joined(separator: "|")
    }

    var accessibilityText: String {
        [
            self.titleText,
            "\(L("Today")) \(self.todaySpendText)",
            "\(L("Tokens")) \(self.tokenText)",
            "\(L("Calls")) \(self.callText)",
        ].joined(separator: ", ")
    }
}

struct OverviewUsageCardView: View {
    let model: OverviewUsageCardModel
    let width: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(self.model.titleText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.58))
                    .lineLimit(1)
                Text(self.model.totalSpendText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 14) {
                self.fact(L("Today"), self.model.todaySpendText)
                self.fact(L("Tokens"), self.model.tokenText)
                self.fact(L("Calls"), self.model.callText)
            }
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
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5))
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .frame(width: self.width, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(self.model.accessibilityText)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.38))
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
        }
        .fixedSize()
    }
}
