import AppKit
import CodexBarCore
import SwiftUI

/// The top of the Overview menu: app icon, title and last-update subtitle on the left, the round
/// refresh and settings buttons on the right. The buttons are real hosted controls; the row itself
/// never highlights.
struct OverviewCardHeaderView: View {
    let title: String
    let updatedText: String
    let width: CGFloat
    @Environment(\.providerCardAction) private var cardAction
    @Environment(\.menuCardRefreshMonitor) private var refreshMonitor

    private var isRefreshing: Bool {
        self.refreshMonitor?.isManualRefreshInFlight ?? false
    }

    var body: some View {
        HStack(spacing: 10) {
            if let icon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(self.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(self.updatedText)
                    .font(.system(size: 11))
                    .foregroundStyle(OverviewPalette.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            self.refreshButton
            self.button(systemName: "gearshape", label: L("Settings..."), action: .settings)
        }
        .padding(.horizontal, OverviewCompactAccountRow.horizontalPadding)
        .padding(.vertical, 8)
        .frame(width: self.width, alignment: .leading)
    }

    /// The refresh affordance spins down to a progress indicator while a manual refresh runs, the
    /// same feedback the old footer bar gave through its icon animation.
    private var refreshButton: some View {
        Button {
            self.cardAction.perform?(.refresh)
        } label: {
            Group {
                if self.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .frame(width: 30, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.08)))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(L("Refresh"))
        .menuCardInteractiveControl()
    }

    private func button(
        systemName: String,
        label: String,
        action: MenuDescriptor.MenuAction) -> some View
    {
        Button {
            self.cardAction.perform?(action)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.85))
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(label)
        .menuCardInteractiveControl()
    }
}

/// The "N providers" line with the Now / 5h / 7d segmented control. Segments are hosted buttons so
/// the choice applies without closing the menu; the selection is persisted by the caller's closure.
struct OverviewWindowFilterBarView: View {
    let providerCount: Int
    let selection: OverviewWindowFilter
    let onSelect: (OverviewWindowFilter) -> Void
    let width: CGFloat

    var body: some View {
        HStack {
            Text(L("%lld providers", self.providerCount))
                .font(.system(size: 12))
                .foregroundStyle(OverviewPalette.caption)
                .lineLimit(1)
            Spacer(minLength: 8)
            self.segmentedControl
        }
        .padding(.horizontal, OverviewCompactAccountRow.horizontalPadding)
        .padding(.vertical, 4)
        .frame(width: self.width, alignment: .leading)
    }

    private var segmentedControl: some View {
        HStack(spacing: 2) {
            ForEach(OverviewWindowFilter.allCases, id: \.rawValue) { filter in
                Button {
                    self.onSelect(filter)
                } label: {
                    Text(filter.segmentTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(self.selection == filter ? Color.white : OverviewPalette.caption)
                        .frame(minWidth: 38, minHeight: 20)
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(self.selection == filter ? Color.white.opacity(0.16) : .clear))
                }
                .buttonStyle(.plain)
                .menuCardInteractiveControl()
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}

/// The bottom line of the Overview menu: whether auto-refresh runs, and when data last landed.
struct OverviewFooterStatusView: View {
    let autoRefreshOn: Bool
    let lastSyncText: String
    let width: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(self.autoRefreshOn
                    ? Color(red: 0.24, green: 0.84, blue: 0.44)
                    : OverviewPalette.neutral)
                .frame(width: 7, height: 7)
            Text(self.autoRefreshOn ? L("Auto-refresh on") : L("Auto-refresh off"))
                .font(.system(size: 11))
                .foregroundStyle(OverviewPalette.caption)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(self.lastSyncText)
                .font(.system(size: 11))
                .foregroundStyle(OverviewPalette.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, OverviewCompactAccountRow.horizontalPadding)
        .padding(.vertical, 6)
        .frame(width: self.width, alignment: .leading)
    }
}
