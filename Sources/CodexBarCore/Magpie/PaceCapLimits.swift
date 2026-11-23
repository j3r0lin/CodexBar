import Foundation

/// The daily allowances the local pace-cap hook writes to `~/.config/magpie/pace-cap/limits.json`, keyed
/// like magpie's quota rows: provider wire ID, raw `user`, window name. magpie's quota response carries no
/// allowance of its own, so these are joined onto its windows after each read.
public struct PaceCapLimits: Sendable, Equatable {
    public struct Account: Sendable, Equatable, Decodable {
        public let provider: String
        public let user: String
        public let window: String
        public let allowance: Double
    }

    public let accounts: [Account]

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/magpie/pace-cap/limits.json")
    }

    /// nil when the file is missing or unreadable: the windows then show no allowance.
    public static func read(from url: URL = Self.defaultURL) -> PaceCapLimits? {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        return PaceCapLimits(accounts: file.accounts.compactMap(\.value))
    }

    /// The rows with each window's allowance attached.
    public func applied(to rows: [MagpieQuotaRow]) -> [MagpieQuotaRow] {
        rows.map { row in
            let user = row.organization.isEmpty
                ? row.email : row.email + MagpieQuotasReader.userSeparator + row.organization
            let mine = self.accounts.filter { $0.provider == row.provider && $0.user == user }
            guard !mine.isEmpty else { return row }
            let windows = row.windows.map { window in
                var limited = window
                limited.dailyAllowance = mine.first { $0.window == window.name }?.allowance
                return limited
            }
            return MagpieQuotaRow(
                provider: row.provider,
                email: row.email,
                organization: row.organization,
                alias: row.alias,
                isLast: row.isLast,
                readAt: row.readAt,
                windows: windows,
                error: row.error,
                resetCredits: row.resetCredits,
                name: row.name,
                plan: row.plan)
        }
    }

    private struct File: Decodable {
        let accounts: [Lenient<Account>]
    }
}
