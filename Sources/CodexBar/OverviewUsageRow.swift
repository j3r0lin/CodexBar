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

        init(window: MagpieQuotaWindow) {
            self.label = Self.label(for: window)
            self.title = Self.title(for: window)
            self.used = min(100, max(0, window.usedPercent))
            self.resetsAt = window.resetsAt
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

    var isMagpie: Bool { self.namedWindows != nil }

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
