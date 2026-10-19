import Foundation

/// Stable identity for one account row surfaced by a multi-account source adapter.
///
/// `source` names the adapter (for example `claude-swap`) and `opaqueID` is the
/// source-issued identifier (for example a numeric slot). Identity never derives
/// from emails or credential material, per
/// `docs/claude-multi-account-and-status-items.md`.
public struct ProviderAccountIdentity: Hashable, Sendable {
    public let source: String
    public let opaqueID: String

    public init(source: String, opaqueID: String) {
        self.source = source
        self.opaqueID = opaqueID
    }
}

/// Provider-neutral projection of one account's usage, consumed by menus (and,
/// later, per-account status items) without teaching UI code about any specific
/// credential source.
public struct ProviderAccountUsageSnapshot: Identifiable, Sendable {
    public let id: ProviderAccountIdentity
    public let provider: UsageProvider
    /// Display-only label (may contain personal data such as an email); UI is
    /// responsible for privacy redaction. Never logged or persisted.
    public let displayLabel: String
    /// Display-only source email, kept separate from `displayLabel` so aliases and
    /// `email · org` disambiguation cannot leak into identity.
    public let accountEmail: String?
    /// Opaque, source-owned history scope; independent of the activation slot and sync identity.
    public let historyAccountKey: String?
    public let isActive: Bool
    /// Whether the source can activate this slot or explicitly repair its selected credential state.
    /// Activation remains source-owned; CodexBar never handles credential material.
    public let canActivate: Bool
    /// Whether `snapshot` is a last-known measurement the source served because
    /// live usage was unavailable, rather than a current one. Such a snapshot is
    /// fine on a card that shows its age, but must not drive age-less surfaces.
    public let usesLastKnownUsage: Bool
    public let snapshot: UsageSnapshot?
    public let error: String?
    public let sourceLabel: String?
    /// 1-based position in the source's own listing, for sources without numeric slots. Privacy-safe
    /// `Account N` labels use it; it is never identity.
    public let sourceOrdinal: Int?

    public init(
        id: ProviderAccountIdentity,
        provider: UsageProvider,
        displayLabel: String,
        accountEmail: String? = nil,
        historyAccountKey: String? = nil,
        isActive: Bool,
        canActivate: Bool = false,
        usesLastKnownUsage: Bool = false,
        snapshot: UsageSnapshot?,
        error: String?,
        sourceLabel: String?,
        sourceOrdinal: Int? = nil)
    {
        self.sourceOrdinal = sourceOrdinal
        self.id = id
        self.provider = provider
        self.displayLabel = displayLabel
        self.accountEmail = accountEmail
        self.historyAccountKey = historyAccountKey
        self.isActive = isActive
        self.canActivate = canActivate
        self.usesLastKnownUsage = usesLastKnownUsage
        self.snapshot = snapshot
        self.error = error
        self.sourceLabel = sourceLabel
    }

    /// The same account, with its usage marked as a last-known measurement and an explanatory error.
    public func retainedAsLastKnown(error: String) -> ProviderAccountUsageSnapshot {
        ProviderAccountUsageSnapshot(
            id: self.id,
            provider: self.provider,
            displayLabel: self.displayLabel,
            accountEmail: self.accountEmail,
            historyAccountKey: self.historyAccountKey,
            isActive: self.isActive,
            canActivate: self.canActivate,
            usesLastKnownUsage: self.snapshot != nil,
            snapshot: self.snapshot,
            error: error,
            sourceLabel: self.sourceLabel,
            sourceOrdinal: self.sourceOrdinal)
    }
}
