import Foundation

/// Projects magpie account snapshots into the native `UsageSnapshot` shape, for surfaces that
/// still speak the native model (menu bar icon, widgets, token-account style cards). Window
/// slots follow each provider's own convention: Kimi's primary window is the weekly one, not a
/// Claude-style session-first layout. Cost, credits, and history stay empty — magpie reports
/// usage only and missing data is never shown as zero.
public enum MagpieUsageProjection {
    public static func usageSnapshot(
        for account: MagpieAccountSnapshot,
        now: Date = Date()) -> UsageSnapshot?
    {
        guard account.error != MagpieAccountProjection.unstableIdentityError,
              let provider = account.provider.nativeProvider else { return nil }
        let session = account.limitedWindows.first { $0.semantics == .session }
        let weekly = account.limitedWindows.first { $0.semantics == .weekly }
        let monthly = account.limitedWindows.first { $0.semantics == .monthly }
        let scoped = account.limitedWindows.compactMap { window -> ClaudeScopedWeeklyLimitMapper.Limit? in
            guard case let .scopedWeekly(model) = window.semantics else { return nil }
            return ClaudeScopedWeeklyLimitMapper.Limit(
                kind: "weekly_scoped",
                group: "weekly",
                percent: window.usedPercent,
                resetsAt: window.resetsAt,
                modelID: nil,
                modelName: model)
        }
        let extra = ClaudeScopedWeeklyLimitMapper.extraRateWindows(from: scoped)

        let primary: RateWindow?
        let secondary: RateWindow?
        let tertiary: RateWindow?
        switch provider {
        // Provider-specific by design: Kimi native slots are weekly first, session second.
        case .kimi:
            // Kimi's native layout is primary=weekly, secondary=session.
            primary = weekly.map(self.rateWindow)
            secondary = session.map(self.rateWindow)
            tertiary = monthly.map(self.rateWindow)
        // Provider-specific by design: native Grok carries its whole quota in primary
        // (GrokStatusProbe), and every Grok label path reads only that slot.
        case .grok:
            primary = (weekly ?? monthly).map(self.rateWindow)
            secondary = nil
            tertiary = nil
        default:
            primary = session.map(self.rateWindow)
            secondary = weekly.map(self.rateWindow)
            tertiary = monthly.map(self.rateWindow)
        }
        guard primary != nil || secondary != nil || tertiary != nil || !extra.isEmpty else { return nil }
        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            extraRateWindows: extra.isEmpty ? nil : extra,
            updatedAt: account.readAt ?? now,
            identity: ProviderIdentitySnapshot(
                providerID: provider.instanceID,
                accountEmail: account.accountEmail,
                accountOrganization: nil,
                loginMethod: MagpieAccountProjection.sourceLabel,
                accountID: account.id.opaqueID))
    }

    /// Menu/widget projection for one native provider: the magpie accounts of that provider as
    /// `ProviderAccountUsageSnapshot` rows, active first.
    public static func providerAccountSnapshots(
        for provider: UsageProvider,
        in accounts: [MagpieAccountSnapshot],
        now: Date = Date()) -> [ProviderAccountUsageSnapshot]
    {
        accounts.filter { $0.provider.nativeProvider == provider && !$0.hasOnlyUnlimitedWindows }.map { account in
            let snapshot = self.usageSnapshot(for: account, now: now)
            return ProviderAccountUsageSnapshot(
                id: account.id,
                provider: provider,
                displayLabel: account.displayLabel,
                accountEmail: account.accountEmail,
                isActive: account.isActive,
                canActivate: false,
                usesLastKnownUsage: account.usesLastKnownUsage,
                snapshot: snapshot,
                error: account.error,
                sourceLabel: MagpieAccountProjection.sourceLabel,
                sourceOrdinal: account.ordinal)
        }
    }

    private static func rateWindow(for window: MagpieQuotaWindow) -> RateWindow {
        RateWindow(
            usedPercent: window.usedPercent,
            windowMinutes: window.duration.map { Int($0 / 60) },
            resetsAt: window.resetsAt,
            resetDescription: nil)
    }
}

extension UsageSnapshot {
    /// True when this snapshot was projected from a magpie gateway row rather than read natively.
    /// Source-dependent fallbacks (like Grok's reset-time period inference) must not apply to
    /// magpie windows: their period comes from a known duration or a parseable name only.
    public var isMagpieSourced: Bool {
        self.identity?.loginMethod == MagpieAccountProjection.sourceLabel
    }
}
