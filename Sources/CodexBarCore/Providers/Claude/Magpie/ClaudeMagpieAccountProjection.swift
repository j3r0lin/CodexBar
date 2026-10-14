#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif
import Foundation

public enum ClaudeMagpieQuotasParserError: LocalizedError, Sendable {
    case malformedResponse

    public var errorDescription: String? {
        "magpie returned a quota response CodexBar cannot read."
    }
}

/// Projects magpie `GET /v1/magpie/quotas` rows into provider-neutral Claude account snapshots.
///
/// Identity is `magpie:claude:<lowercased email>`. This deliberately departs from the rule that account identity
/// never derives from email (see `docs/claude-multi-account-and-status-items.md`): magpie issues no slot number or
/// other stable row ID, and the email it reports is the most stable key it offers. When two rows share an email the
/// organization name is appended, matching claude-swap's display disambiguation.
public enum ClaudeMagpieAccountProjection {
    public static let sourceName = "magpie"
    public static let sourceLabel = "magpie"
    static let fiveHourWindowMinutes = 5 * 60
    static let sevenDayWindowMinutes = 7 * 24 * 60
    static let fiveHourWindowName = "5 hours"
    static let sevenDayWindowName = "7 days"
    static let scopedWeeklyPrefix = "7 days · "
    static let userSeparator = " · "

    /// Opaque key for surfaces that persist account identity (widgets), so the email in `opaqueID` is never stored.
    public static func ownershipFingerprint(for account: ProviderAccountUsageSnapshot) -> String? {
        guard account.id.source == self.sourceName else { return nil }
        return SHA256.hash(data: Data(account.id.opaqueID.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func accountSnapshots(from data: Data, now: Date = Date()) throws
        -> [ProviderAccountUsageSnapshot]
    {
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ClaudeMagpieQuotasParserError.malformedResponse
        }
        let rows = response.data.compactMap(\.value).filter { $0.provider == "claude" }.map(Account.init)
        return self.accountSnapshots(from: rows, now: now)
    }

    private static func accountSnapshots(from allRows: [Account], now: Date) -> [ProviderAccountUsageSnapshot] {
        // Rows without an email have no stable identity, so they are not shown.
        let emailRows = allRows.filter { !$0.email.isEmpty }
        let emailCounts = emailRows.reduce(into: [String: Int]()) { counts, row in
            counts[row.email.lowercased(), default: 0] += 1
        }
        var seenKeys: Set<String> = []
        let rows = emailRows.compactMap { row -> (row: Account, key: String, duplicated: Bool)? in
            let duplicated = emailCounts[row.email.lowercased(), default: 0] > 1
            let key = self.identityKey(for: row, duplicated: duplicated)
            // A repeated email and organization cannot be told apart; keep the first row.
            guard seenKeys.insert(key).inserted else { return nil }
            return (row, key, duplicated)
        }
        let activeIndex = rows.firstIndex(where: \.row.isLast) ?? (rows.isEmpty ? nil : 0)
        let projected = rows.enumerated().map { index, entry -> ProviderAccountUsageSnapshot in
            let id = ProviderAccountIdentity(source: self.sourceName, opaqueID: "claude:\(entry.key)")
            let snapshot = self.usageSnapshot(for: entry.row, accountID: id.opaqueID, now: now)
            return ProviderAccountUsageSnapshot(
                id: id,
                provider: .claude,
                displayLabel: self.displayLabel(for: entry.row, duplicated: entry.duplicated),
                accountEmail: entry.row.email,
                isActive: index == activeIndex,
                canActivate: false,
                snapshot: snapshot,
                error: snapshot == nil ? "No usage windows reported." : nil,
                sourceLabel: self.sourceLabel,
                sourceOrdinal: index + 1)
        }
        // Active first, then magpie's own order, matching the claude-swap card order.
        return projected.filter(\.isActive) + projected.filter { !$0.isActive }
    }

    private static func identityKey(for row: Account, duplicated: Bool) -> String {
        guard duplicated, !row.organization.isEmpty else { return row.email.lowercased() }
        return "\(row.email.lowercased())\(self.userSeparator)\(row.organization.lowercased())"
    }

    private static func displayLabel(for row: Account, duplicated: Bool) -> String {
        if let alias = row.alias { return alias }
        if duplicated, !row.organization.isEmpty {
            return "\(row.email)\(self.userSeparator)\(row.organization)"
        }
        return row.email
    }

    private static func usageSnapshot(for row: Account, accountID: String, now: Date) -> UsageSnapshot? {
        var primary: RateWindow?
        var secondary: RateWindow?
        var scoped: [ClaudeScopedWeeklyLimitMapper.Limit] = []
        for window in row.windows {
            // Negative usage is malformed; values above 100 are reported as-is.
            guard let used = window.used, used.isFinite, used >= 0, let name = window.name else { continue }
            let resetsAt = ISO8601DateParser.parse(window.resetsAt)
            if name == self.fiveHourWindowName {
                primary = RateWindow(
                    usedPercent: used,
                    windowMinutes: self.fiveHourWindowMinutes,
                    resetsAt: resetsAt,
                    resetDescription: nil)
            } else if name == self.sevenDayWindowName {
                secondary = RateWindow(
                    usedPercent: used,
                    windowMinutes: self.sevenDayWindowMinutes,
                    resetsAt: resetsAt,
                    resetDescription: nil)
            } else if name.hasPrefix(self.scopedWeeklyPrefix) {
                scoped.append(ClaudeScopedWeeklyLimitMapper.Limit(
                    kind: "weekly_scoped",
                    group: "weekly",
                    percent: used,
                    resetsAt: resetsAt,
                    modelID: nil,
                    modelName: String(name.dropFirst(self.scopedWeeklyPrefix.count))))
            }
        }
        let extra = ClaudeScopedWeeklyLimitMapper.extraRateWindows(from: scoped)
        guard primary != nil || secondary != nil || !extra.isEmpty else { return nil }
        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            extraRateWindows: extra.isEmpty ? nil : extra,
            updatedAt: ISO8601DateParser.parse(row.readAt) ?? now,
            identity: ProviderIdentitySnapshot(
                providerID: .claude,
                accountEmail: row.email.isEmpty ? nil : row.email,
                accountOrganization: nil,
                loginMethod: self.sourceLabel,
                accountID: "\(self.sourceName):\(accountID)"))
    }

    // MARK: - Wire format

    private struct Response: Decodable {
        let data: [Lenient<Row>]
    }

    /// One malformed row must not discard its siblings.
    private struct Lenient<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) throws {
            self.value = try? Value(from: decoder)
        }
    }

    private struct Row: Decodable {
        let provider: String
        let user: String?
        let alias: String?
        let last: Bool?
        let readAt: String?
        let windows: [Lenient<Window>]?
    }

    private struct Window: Decodable {
        let name: String?
        let used: Double?
        let resetsAt: String?
    }

    private struct Account {
        let email: String
        let organization: String
        let alias: String?
        let isLast: Bool
        let readAt: String?
        let windows: [Window]

        init(_ row: Row) {
            // magpie formats `user` as "<email> · <organization>"; either side may be absent.
            let user = row.user?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let range = user.range(of: ClaudeMagpieAccountProjection.userSeparator) {
                self.email = String(user[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                self.organization = String(user[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                self.email = user
                self.organization = ""
            }
            let alias = row.alias?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.alias = alias.isEmpty ? nil : alias
            self.isLast = row.last == true
            self.readAt = row.readAt
            self.windows = (row.windows ?? []).compactMap(\.value)
        }
    }
}
