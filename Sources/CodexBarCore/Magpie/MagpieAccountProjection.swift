#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

/// One magpie-reported account row for one provider, in the narrow magpie model.
///
/// Identified accounts use an opaque fingerprint of provider, email, and organization. A sole
/// anonymous row uses a provider-level fingerprint; ambiguous anonymous rows use display-only
/// ordinal fingerprints and cannot own ambient usage.
public struct MagpieAccountSnapshot: Identifiable, Sendable, Equatable {
    public let id: ProviderAccountIdentity
    public let provider: MagpieProviderReference
    /// Display-only label (may contain personal data such as an email); UI redacts in privacy mode.
    public let displayLabel: String
    public let accountEmail: String?
    /// 1-based position within this provider's own listing; privacy-safe `Account N` labels use it.
    public let ordinal: Int
    public let windows: [MagpieQuotaWindow]
    public var limitedWindows: [MagpieQuotaWindow] {
        self.windows.filter { !$0.unlimited }
    }

    public var hasOnlyUnlimitedWindows: Bool {
        !self.windows.isEmpty && self.windows.allSatisfy(\.unlimited)
    }

    public let readAt: Date?
    public let isActive: Bool
    public let usesLastKnownUsage: Bool
    public let error: String?
    public let resetCredits: MagpieResetCredits?

    public init(
        id: ProviderAccountIdentity,
        provider: MagpieProviderReference,
        displayLabel: String,
        accountEmail: String?,
        ordinal: Int,
        windows: [MagpieQuotaWindow],
        readAt: Date?,
        isActive: Bool,
        usesLastKnownUsage: Bool = false,
        error: String?,
        resetCredits: MagpieResetCredits? = nil)
    {
        self.id = id
        self.provider = provider
        self.displayLabel = displayLabel
        self.accountEmail = accountEmail
        self.ordinal = ordinal
        self.windows = windows
        self.readAt = readAt
        self.isActive = isActive
        self.usesLastKnownUsage = usesLastKnownUsage
        self.error = error
        self.resetCredits = resetCredits
    }

    /// The same account, with its usage marked as a last-known measurement and an explanatory error.
    public func retainedAsLastKnown(error: String?) -> MagpieAccountSnapshot {
        MagpieAccountSnapshot(
            id: self.id,
            provider: self.provider,
            displayLabel: self.displayLabel,
            accountEmail: self.accountEmail,
            ordinal: self.ordinal,
            windows: self.windows,
            readAt: self.readAt,
            isActive: self.isActive,
            usesLastKnownUsage: !self.windows.isEmpty,
            error: error,
            resetCredits: self.resetCredits)
    }
}

public enum MagpieAccountProjection {
    public static let sourceName = "magpie"
    public static let sourceLabel = "magpie"

    /// Error shown for rows whose wire `user` carries no email, so identity cannot be derived.
    public static let unstableIdentityError = "magpie did not report a stable account identity for this row."

    /// Opaque fingerprint of (wire provider, lowercased email, lowercased organization). Persisted
    /// surfaces (widgets) store this instead of any email-bearing identifier.
    public static func identityFingerprint(wireID: String, email: String, organization: String) -> String {
        let key = "\(self.sourceName)\u{0}\(wireID)\u{0}\(email.lowercased())\u{0}\(organization.lowercased())"
        return SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func ownershipFingerprint(for account: MagpieAccountSnapshot) -> String? {
        guard account.id.source == self.sourceName else { return nil }
        return account.id.opaqueID
    }

    /// Projects all rows into account snapshots, preserving every provider magpie returns,
    /// including unknown ones. Rows are grouped by provider; within a provider the active row
    /// comes first, matching the source's own order otherwise. Wire IDs that name the same
    /// native provider merge into one group — one card per account and a single active row —
    /// while unknown providers stay keyed by their own wire ID.
    public static func snapshots(from rows: [MagpieQuotaRow]) -> [MagpieAccountSnapshot] {
        var wireOrder: [String] = []
        var rowsByWire: [String: [MagpieQuotaRow]] = [:]
        for row in rows {
            if rowsByWire[row.provider] == nil { wireOrder.append(row.provider) }
            rowsByWire[row.provider, default: []].append(row)
        }
        var groupOrder: [String] = []
        var groups: [String: (reference: MagpieProviderReference, rows: [MagpieQuotaRow])] = [:]
        for wireID in wireOrder {
            let reference = MagpieProviderMapping.reference(for: wireID)
            guard let native = reference.nativeProvider else {
                // Prefixed keys: an unknown wire ID that spells a mapped provider's raw value
                // ("opencodego" vs opencode-go's .opencodego) must never collide with the native group.
                let key = "wire:\(wireID)"
                groupOrder.append(key)
                groups[key] = (reference, rowsByWire[wireID] ?? [])
                continue
            }
            let key = "native:\(native.rawValue)"
            if var group = groups[key] {
                group.rows.append(contentsOf: rowsByWire[wireID] ?? [])
                groups[key] = group
            } else {
                groupOrder.append(key)
                // The group's identity follows the provider's deterministic first wire ID,
                // never whichever spelling the response happened to carry.
                let canonical = MagpieProviderMapping.wireID(for: native) ?? wireID
                groups[key] = (MagpieProviderMapping.reference(for: canonical), rowsByWire[wireID] ?? [])
            }
        }
        return groupOrder.flatMap { key -> [MagpieAccountSnapshot] in
            guard let group = groups[key] else { return [] }
            // The same account under two wire IDs of one provider keeps the canonical row.
            let canonical = group.reference.wireID
            let canonicalRows = group.rows.filter { $0.provider == canonical }
            var ordered = canonicalRows
            // One provider-level (user-less) row per provider: a second spelling's anonymous
            // row would otherwise turn both into ambiguous-identity error cards.
            let canonicalHasAnonymous = canonicalRows.contains { $0.email.isEmpty }
            for row in group.rows where row.provider != canonical {
                if row.email.isEmpty, canonicalHasAnonymous { continue }
                ordered.append(row)
            }
            return self.snapshots(for: group.reference, rows: ordered)
        }
    }

    private static func snapshots(
        for reference: MagpieProviderReference,
        rows allRows: [MagpieQuotaRow]) -> [MagpieAccountSnapshot]
    {
        // The same email and organization (compared case-insensitively) is the same account and
        // keeps its first row. Distinct organizations under one email stay separate accounts.
        var seenRows: Set<String> = []
        let uniqueRows = allRows.filter { row in
            row.email.isEmpty ||
                seenRows.insert("\(row.email.lowercased())\u{0}\(row.organization.lowercased())").inserted
        }
        let emailCounts = uniqueRows.reduce(into: [String: Int]()) { counts, row in
            counts[row.email.lowercased(), default: 0] += 1
        }
        let activeIndex = uniqueRows.firstIndex(where: \.isLast) ?? (uniqueRows.isEmpty ? nil : 0)
        let projected = uniqueRows.enumerated().map { index, row -> MagpieAccountSnapshot in
            let duplicated = !row.email.isEmpty && emailCounts[row.email.lowercased(), default: 0] > 1
            let providerIdentity = row.email.isEmpty && allRows.count == 1
            let ambiguousIdentity = row.email.isEmpty && !providerIdentity
            let fingerprint = ambiguousIdentity
                ? self.identityFingerprint(wireID: reference.wireID, email: "\u{0}anonymous:\(index)", organization: "")
                : self.identityFingerprint(
                    wireID: reference.wireID,
                    email: providerIdentity ? "\u{0}provider" : row.email,
                    organization: providerIdentity ? "" : row.organization)
            let identityError = ambiguousIdentity ? self.unstableIdentityError : nil
            return MagpieAccountSnapshot(
                id: ProviderAccountIdentity(source: self.sourceName, opaqueID: fingerprint),
                provider: reference,
                displayLabel: row.email.isEmpty
                    ? reference.displayName
                    : self.displayLabel(for: row, reference: reference, duplicated: duplicated),
                accountEmail: row.email.isEmpty ? nil : row.email,
                ordinal: index + 1,
                windows: row.windows,
                readAt: row.readAt,
                isActive: !ambiguousIdentity && index == activeIndex,
                error: identityError ?? row.error,
                resetCredits: row.resetCredits)
        }
        return projected.filter(\.isActive) + projected.filter { !$0.isActive }
    }

    private static func displayLabel(
        for row: MagpieQuotaRow,
        reference: MagpieProviderReference,
        duplicated: Bool) -> String
    {
        if let alias = row.alias { return alias }
        if duplicated, !row.organization.isEmpty {
            return "\(row.email) · \(row.organization)"
        }
        if !row.email.isEmpty { return row.email }
        return reference.displayName
    }
}
