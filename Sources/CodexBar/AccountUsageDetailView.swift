import CodexBarCore
import SwiftUI

/// Usage detail of one account or provider: short and long window bars with percent and reset, and data age.
/// Shared by the Overview row submenus and the menu-bar ring hover card.
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
                Text("No usage data").font(.system(size: 11)).foregroundStyle(.secondary)
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
                    Text("\(Int(used.rounded()))%"
                        + (window.resetsAt.map {
                            " · resets in " + OverviewCompactAccountRow.countdown(to: $0, now: self.now)
                        } ?? ""))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.22))
                        Capsule()
                            .fill(Color(nsColor: UsageSeverityPalette.color(usedPercent: used)))
                            .frame(width: proxy.size.width * used / 100)
                    }
                }
                .frame(height: 5)
            }
        }
    }

    private static func windowTitle(_ window: RateWindow) -> String {
        guard let minutes = window.windowMinutes else { return "Window" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) days" }
        if minutes % 60 == 0 { return "\(minutes / 60) hours" }
        return "\(minutes) minutes"
    }

    static func ageText(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        return minutes < 1 ? "Updated just now" : "Updated \(minutes)m ago"
    }
}
