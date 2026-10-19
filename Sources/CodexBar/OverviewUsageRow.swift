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
        /// The filter bucket this window belongs to; the label stays display-only.
        let kind: OverviewWindowFilter.WindowKind

        init(window: MagpieQuotaWindow) {
            self.label = Self.label(for: window)
            self.title = Self.title(for: window)
            self.used = min(100, max(0, window.usedPercent))
            self.resetsAt = window.resetsAt
            self.kind = Self.kind(for: window)
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

        private static func kind(for window: MagpieQuotaWindow) -> OverviewWindowFilter.WindowKind {
            switch window.semantics {
            case .session: .session
            case .weekly, .scopedWeekly: .weekly
            case .monthly, .other: .other
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
    var namedWindows: [NamedWindow]?
    /// Native rows only: the snapshot behind the window slots and the detail card.
    let snapshot: UsageSnapshot?
    /// Native rows only: the card model behind the hover chart and provider actions.
    let model: UsageMenuCardView.Model?
    /// Native rows only, set by `filtered(to:)`: the window slots that survive the active
    /// Overview filter, replacing the slots the row view would otherwise derive from `snapshot`.
    var slotOverride: (short: RateWindow?, long: RateWindow?)?
    /// Replaces the usage lines when set; used for native overview errors and for magpie rows
    /// whose account has no windows to show.
    let errorText: String?
    /// The account carries an error alongside its usage (last-known retention, unstable
    /// identity); the row keeps its readings and flags the name instead.
    let showsErrorFlag: Bool
    /// Shown in the detail card under the window blocks, e.g. a last-known retention note.
    let detailErrorText: String?

    var isMagpie: Bool {
        self.namedWindows != nil
    }

    /// Applies the Overview window filter: keeps only the windows the filter admits and returns nil
    /// when nothing matches, so the caller drops the row. Error-only rows carry no window and are
    /// hidden by either filter. Under `.now` the row is returned unchanged.
    @MainActor
    func filtered(to filter: OverviewWindowFilter) -> OverviewUsageRow? {
        guard filter != .now else { return self }
        var copy = self
        if let windows = self.namedWindows {
            let kept = windows.filter { filter.includes($0.kind) }
            guard !kept.isEmpty else { return nil }
            copy.namedWindows = kept
            return copy
        }
        guard self.errorText == nil else { return nil }
        let slots = OverviewCompactAccountRow.slots(of: self.snapshot, provider: self.nativeProvider)
        let infersPeriod = !self.isMagpie
        let short = slots.short.flatMap { window in
            filter.includes(OverviewCompactAccountRow.windowKind(
                of: window, provider: self.nativeProvider, infersPeriodFromReset: infersPeriod))
                ? window
                : nil
        }
        let long = slots.long.flatMap { window in
            filter.includes(OverviewCompactAccountRow.windowKind(
                of: window, provider: self.nativeProvider, infersPeriodFromReset: infersPeriod))
                ? window
                : nil
        }
        guard short != nil || long != nil else { return nil }
        copy.slotOverride = (short: short, long: long)
        return copy
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
            detailErrorText: nil)
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
            detailErrorText: account.error)
    }
}
