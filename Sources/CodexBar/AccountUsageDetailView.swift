import CodexBarCore
import SwiftUI

/// Usage detail of one account or provider: short and long window bars with percent and reset, and data age.
/// Shown in the Overview row's detail submenu.
struct AccountUsageDetailView: View {
    static let defaultWidth: CGFloat = 240

    let name: String
    let snapshot: UsageSnapshot?
    var width: CGFloat = Self.defaultWidth
    var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(self.name).font(.system(size: 13, weight: .semibold))
            if let snapshot {
                self.windowRow(snapshot.primary)
                self.windowRow(snapshot.secondary)
                Text(Self.ageText(snapshot.updatedAt, now: self.now))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text(L("No data")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(width: self.width - 24, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: self.width, alignment: .leading)
    }

    @ViewBuilder
    private func windowRow(_ window: RateWindow?) -> some View {
        if let window, let used = OverviewCompactAccountRow.used(window) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(Self.windowTitle(window)).font(.system(size: 11))
                    Spacer()
                    Text(Self.usageText(used: used, resetsAt: window.resetsAt, now: self.now))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(OverviewCompactAccountRow.trackColor)
                        Capsule()
                            .fill(Color(nsColor: UsageSeverityPalette.color(usedPercent: used)))
                            .frame(width: proxy.size.width * used / 100)
                    }
                }
                .frame(height: 5)
            }
        }
    }

    static func windowTitle(_ window: RateWindow) -> String {
        guard let minutes = window.windowMinutes else { return L("Window") }
        if minutes % 1440 == 0 { return L("account_detail_window_days", minutes / 1440) }
        if minutes % 60 == 0 { return L("account_detail_window_hours", minutes / 60) }
        return L("account_detail_window_minutes", minutes)
    }

    static func usageText(used: Double, resetsAt: Date?, now: Date) -> String {
        let percent = "\(Int(used.rounded()))%"
        guard let resetsAt else { return percent }
        return percent + " · " + L("Resets in %@", OverviewCompactAccountRow.countdown(to: resetsAt, now: now))
    }

    static func ageText(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        return minutes < 1 ? L("Updated just now") : L("Updated %@m ago", String(minutes))
    }
}
