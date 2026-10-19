import CodexBarCore
import Foundation

/// One row in the merged Overview: a native provider row, or one magpie account row for any
/// provider the gateway reported, known or unknown. Magpie rows carry every window the gateway
/// sent under its own label and have no native history, cost, credits, or provider actions.
struct OverviewUsageRow {
    /// One quota window on a magpie row: `label` is the compact tag on the row ("5h", "7d",
    /// "Mo", a model name, or the wire name), `title` the heading in the detail card.
    struct NamedWindow: Equatable {
        let label: String
        let title: String
        let used: Double
        let resetsAt: Date?
        /// Window length when the gateway or the window's name fixes it; month and unknown windows
        /// have none and therefore no pace.
        let duration: TimeInterval?
        /// The quota-warning settings that govern this window; nil for month and unknown windows.
        let quotaWarningWindow: QuotaWarningWindow?

        init(window: MagpieQuotaWindow) {
            self.label = Self.label(for: window)
            self.title = Self.title(for: window)
            self.used = min(100, max(0, window.usedPercent))
            self.resetsAt = window.resetsAt
            self.duration = window.duration
            self.quotaWarningWindow = switch window.semantics {
            case .session: .session
            case .weekly, .scopedWeekly: .weekly
            case .monthly, .other: nil
            }
        }

        /// Linear pace from this window's own reading, never from another account's history. Windows
        /// without a known length have none, and a day-or-shorter window waits for 3% of its time
        /// to pass so a fresh reset does not project nonsense.
        func pace(now: Date) -> UsagePace? {
            guard let duration, duration > 0 else { return nil }
            let window = RateWindow(
                usedPercent: self.used,
                windowMinutes: Int(duration / 60),
                resetsAt: self.resetsAt,
                resetDescription: nil)
            guard let pace = UsagePace.weekly(window: window, now: now) else { return nil }
            if duration <= 86400, pace.expectedUsedPercent < 3 { return nil }
            return pace
        }

        /// Slots and labels follow the window's semantics, never its reset-description text:
        /// "5 hours" is 5h, "7 days" is 7d, "Month" is Mo.
        private static func label(for window: MagpieQuotaWindow) -> String {
            switch window.semantics {
            case .session: "5h"
            case .weekly: "7d"
            case .monthly: "Mo"
            case let .scopedWeekly(model): model
            case .other: window.name
            }
        }

        private static func title(for window: MagpieQuotaWindow) -> String {
            switch window.semantics {
            case .session: L("5-hour limit")
            case .weekly: L("Weekly limit")
            case .monthly: L("Monthly limit")
            case .scopedWeekly, .other: window.name
            }
        }
    }

    /// Grouping key: the provider's raw value for native rows, the wire ID for magpie rows.
    let groupKey: String
    /// Provider display name (the raw wire ID for unknown magpie providers).
    let providerName: String
    /// Nil for magpie providers with no native counterpart.
    let nativeProvider: UsageProvider?
    /// The magpie account this row shows; nil on native rows.
    let accountID: ProviderAccountIdentity?
    /// Privacy-aware account label, shown on grouped rows and in the detail header.
    let accountName: String?
    /// Every window the gateway reported for this account; non-nil marks a magpie row.
    let namedWindows: [NamedWindow]?
    /// Native rows only: the snapshot behind the window slots and the detail card.
    let snapshot: UsageSnapshot?
    /// Native rows only: the card model behind the hover chart and provider actions.
    let model: UsageMenuCardView.Model?
    /// Replaces the usage lines when set; used for native overview errors and for magpie rows
    /// whose account has no windows to show.
    let errorText: String?
    /// The account carries an error alongside its usage (last-known retention, unstable
    /// identity); the row keeps its readings and flags the name instead.
    let showsErrorFlag: Bool
    /// Shown in the detail card under the window blocks, e.g. a last-known retention note.
    let detailErrorText: String?
    /// When the gateway last read this magpie account; nil on native rows.
    let readAt: Date?

    var isMagpie: Bool {
        self.namedWindows != nil
    }

    static func native(
        provider: UsageProvider,
        model: UsageMenuCardView.Model,
        snapshot: UsageSnapshot?,
        providerName: String) -> OverviewUsageRow
    {
        OverviewUsageRow(
            groupKey: provider.rawValue,
            providerName: providerName,
            nativeProvider: provider,
            accountID: nil,
            accountName: nil,
            namedWindows: nil,
            snapshot: snapshot,
            model: model,
            errorText: model.isOverviewErrorOnly ? model.subtitleText : nil,
            showsErrorFlag: false,
            detailErrorText: nil,
            readAt: nil)
    }

    static func magpie(
        account: MagpieAccountSnapshot,
        providerName: String,
        accountName: String) -> OverviewUsageRow
    {
        let windows = account.windows.map(NamedWindow.init(window:))
        return OverviewUsageRow(
            groupKey: account.provider.wireID,
            providerName: providerName,
            nativeProvider: account.provider.nativeProvider,
            accountID: account.id,
            accountName: accountName,
            namedWindows: windows,
            snapshot: nil,
            model: nil,
            errorText: windows.isEmpty ? account.error : nil,
            showsErrorFlag: account.error != nil,
            detailErrorText: account.error,
            readAt: account.readAt)
    }

    /// A reading older than three refresh intervals no longer reflects the account. Manual refresh
    /// has no interval to measure against, and adaptive refresh is measured against a 15-minute
    /// baseline.
    static func staleThreshold(for frequency: RefreshFrequency) -> TimeInterval? {
        switch frequency {
        case .manual: nil
        case .adaptive, .adaptiveAgentAware: 3 * 15 * 60
        default: frequency.seconds.map { 3 * $0 }
        }
    }

    func isStale(now: Date, threshold: TimeInterval?) -> Bool {
        guard let readAt, let threshold else { return false }
        return now.timeIntervalSince(readAt) > threshold
    }

    /// The compact lines of a magpie row. The pace tick and tint go on the longest window that has a
    /// pace, since that is the one a reader plans against.
    func compactLines(now: Date) -> [OverviewCompactAccountRow.Line]? {
        guard let namedWindows else { return nil }
        let paced = namedWindows.compactMap { window in window.pace(now: now).map { (window, $0) } }
        let longest = paced.max { ($0.0.duration ?? 0) < ($1.0.duration ?? 0) }
        return namedWindows.map { window in
            var line = OverviewCompactAccountRow.Line(label: window.label, used: window.used, resetsAt: window.resetsAt)
            if let longest, longest.0 == window {
                line.pacePercent = longest.1.expectedUsedPercent
                line.paceTone = .init(pace: longest.1)
            }
            return line
        }
    }
}
