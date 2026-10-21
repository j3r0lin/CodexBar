import CodexBarCore
import Foundation

/// One row in the merged Overview: a native provider row, or one magpie account row for any
/// provider the gateway reported, known or unknown. Magpie rows carry visible windows under the
/// gateway's labels and have no native cost, credits, or provider actions.
struct OverviewUsageRow {
    /// One quota window on a magpie row: `label` is the compact tag on the row ("5h", "7d",
    /// "30d", a model name, or the wire name), `title` the heading in the detail card.
    struct NamedWindow: Equatable {
        let label: String
        let title: String
        let used: Double
        let resetsAt: Date?
        /// Window length when the gateway or the window's name fixes it; month and unknown windows
        /// have none and therefore no pace.
        let duration: TimeInterval?
        /// magpie's readings of this window, oldest first; empty when it kept none.
        let history: [MagpieQuotaHistoryPoint]

        init(window: MagpieQuotaWindow, history: [MagpieQuotaHistoryPoint] = []) {
            self.label = Self.label(for: window)
            self.title = Self.title(for: window)
            self.used = min(100, max(0, window.usedPercent))
            self.resetsAt = window.resetsAt
            self.duration = window.duration
            self.history = history
        }

        /// Linear pace from this window's own reading, never from another account's history.
        func pace(now: Date) -> UsagePace? {
            OverviewUsageRow.linearPace(used: self.used, duration: self.duration, resetsAt: self.resetsAt, now: now)
        }

        /// The window's current cycle read from its history, nil without readings.
        func trend(now: Date) -> Trend? {
            guard let cycle = MagpieQuotaTrend.currentCycle(points: self.history, resetsAt: self.resetsAt, now: now)
            else { return nil }
            return Trend(
                cycle: cycle,
                readings: self.history.filter { $0.at >= cycle.start && $0.at <= now },
                current: MagpieQuotaTrend.cyclePoints(self.history, cycle: cycle, now: now),
                eta: MagpieQuotaTrend.eta(points: self.history, cycle: cycle, now: now))
        }

        /// Where this window is heading: the run-out fitted to its readings, else the linear pace.
        func outlook(now: Date) -> PaceOutlook? {
            if let eta = self.trend(now: now)?.eta { return PaceOutlook(eta) }
            return self.pace(now: now).flatMap { PaceOutlook(pace: $0, now: now) }
        }

        /// Slots and labels follow the window's semantics, never its reset-description text:
        /// "5 hours" is 5h, "7 days" is 7d, "Month" is 30d, matching the "30 days" windows beside it.
        private static func label(for window: MagpieQuotaWindow) -> String {
            switch window.semantics {
            case .session: "5h"
            case .weekly: "7d"
            case .monthly: "30d"
            case let .scopedWeekly(model): model
            case .other: self.compactDuration(window.name) ?? window.name
            }
        }

        /// "30 days" -> "30d", "12 hours" -> "12h": a long wire name would be truncated in the label column.
        private static func compactDuration(_ name: String) -> String? {
            let parts = name.split(separator: " ")
            guard parts.count == 2, let count = Int(parts[0]) else { return nil }
            switch parts[1].lowercased() {
            case "day", "days": return "\(count)d"
            case "hour", "hours": return "\(count)h"
            default: return nil
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

    /// One window's current cycle from magpie's history: what the side page's curve draws and what the
    /// fitted pace reads.
    struct Trend: Equatable {
        let cycle: MagpieQuotaTrend.Cycle
        /// Readings inside the cycle up to now; a cycle break among them starts a new stretch of line.
        let readings: [MagpieQuotaHistoryPoint]
        /// Readings since the last cycle break, which the shading against the even burn covers.
        let current: [MagpieQuotaHistoryPoint]
        let eta: MagpieQuotaTrend.Eta?
    }

    enum PaceOutlook: Equatable {
        case runsOut(Date)
        case lastsPastReset

        init(_ eta: MagpieQuotaTrend.Eta) {
            switch eta {
            case let .runsOut(date): self = .runsOut(date)
            case .lastsPastReset: self = .lastsPastReset
            }
        }

        init?(pace: UsagePace, now: Date) {
            if pace.willLastToReset {
                self = .lastsPastReset
            } else if let eta = pace.etaSeconds {
                self = .runsOut(now.addingTimeInterval(eta))
            } else {
                return nil
            }
        }
    }

    /// Linear pace of a window with a known length. A day-or-shorter window waits for 3% of its time
    /// to pass so a fresh reset does not project nonsense.
    static func linearPace(used: Double, duration: TimeInterval?, resetsAt: Date?, now: Date) -> UsagePace? {
        guard let duration, duration > 0 else { return nil }
        let window = RateWindow(
            usedPercent: used,
            windowMinutes: Int(duration / 60),
            resetsAt: resetsAt,
            resetDescription: nil)
        guard let pace = UsagePace.weekly(window: window, now: now) else { return nil }
        if duration <= 86400, pace.expectedUsedPercent < 3 { return nil }
        return pace
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
    /// Visible limited windows for this account; non-nil marks a magpie row.
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

    var updatedAt: Date? {
        self.isMagpie ? self.readAt : self.snapshot?.updatedAt
    }

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
        accountName: String,
        history: MagpieQuotaHistory? = nil,
        hiddenItemIDs: Set<ProviderUsageItemID> = []) -> OverviewUsageRow
    {
        let windows = account.limitedWindows.filter { window in
            guard let provider = account.provider.nativeProvider,
                  let itemID = ProviderUsageItemID.magpieWindow(window, for: provider) else { return true }
            return !hiddenItemIDs.contains(itemID)
        }.map { window in
            NamedWindow(
                window: window,
                history: history?.points(for: account.id, window: window.historyName) ?? [])
        }
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

    /// A reading older than three refresh intervals, and at least 30 minutes, no longer reflects the
    /// account. The floor covers magpie reading accounts it rarely serves less often than CodexBar
    /// refreshes. Manual refresh has no interval to measure against, and adaptive refresh is measured
    /// against a 15-minute baseline.
    static func staleThreshold(for frequency: RefreshFrequency) -> TimeInterval? {
        let floor: TimeInterval = 30 * 60
        switch frequency {
        case .manual: return nil
        case .adaptive, .adaptiveAgentAware: return max(floor, 3 * 15 * 60)
        default: return frequency.seconds.map { max(floor, 3 * $0) }
        }
    }

    func isStale(now: Date, threshold: TimeInterval?) -> Bool {
        guard let readAt, let threshold else { return false }
        return now.timeIntervalSince(readAt) > threshold
    }

    /// The compact lines of a magpie row. Every window with a pace gets its tick; the percent tint goes
    /// only on the longest of them, since that is the one a reader plans against.
    func compactLines(now: Date) -> [OverviewCompactAccountRow.Line]? {
        guard let namedWindows else { return nil }
        let paced = namedWindows.compactMap { window in window.pace(now: now).map { (window, $0) } }
        let longest = paced.max { ($0.0.duration ?? 0) < ($1.0.duration ?? 0) }
        return namedWindows.map { window in
            var line = OverviewCompactAccountRow.Line(label: window.label, used: window.used, resetsAt: window.resetsAt)
            line.pacePercent = paced.first { $0.0 == window }?.1.expectedUsedPercent
            if let longest, longest.0 == window {
                line.paceTone = .init(pace: longest.1, fitted: window.trend(now: now)?.eta)
            }
            return line
        }
    }
}
