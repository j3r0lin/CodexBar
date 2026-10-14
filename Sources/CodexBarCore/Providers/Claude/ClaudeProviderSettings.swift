import Foundation

public struct ClaudeProviderSettings: Sendable {
    public let usageDataSource: ClaudeUsageDataSource
    public let webExtrasEnabled: Bool
    public let cookieSource: ProviderCookieSource
    public let manualCookieHeader: String?
    public let organizationID: String?
    /// Non-nil while magpie owns Claude accounts; empty means the default gateway URL. Every Claude fetch then
    /// reads magpie only, so no caller can reach Claude Code credentials, the Keychain, or OAuth.
    public let magpieQuotasURL: String?

    public init(
        usageDataSource: ClaudeUsageDataSource,
        webExtrasEnabled: Bool,
        cookieSource: ProviderCookieSource,
        manualCookieHeader: String?,
        organizationID: String? = nil,
        magpieQuotasURL: String? = nil)
    {
        self.magpieQuotasURL = magpieQuotasURL
        self.usageDataSource = usageDataSource
        self.webExtrasEnabled = webExtrasEnabled
        self.cookieSource = cookieSource
        self.manualCookieHeader = manualCookieHeader
        self.organizationID = organizationID
    }
}

public enum ClaudeProviderSettingsKey: ProviderSettingsSectionKey {
    public static let providerID = ProviderInstanceID.claude
    public typealias Section = ClaudeProviderSettings
}

extension ProviderSettingsSnapshot {
    public typealias ClaudeProviderSettings = CodexBarCore.ClaudeProviderSettings
    public var claude: ClaudeProviderSettings? {
        self[ClaudeProviderSettingsKey.self]
    }

    public static func make(claude: ClaudeProviderSettings?) -> Self {
        self.make(claude, for: ClaudeProviderSettingsKey.self)
    }
}

extension ProviderSettingsSnapshotContribution {
    public static func claude(_ section: ClaudeProviderSettings) -> Self {
        Self(section, for: ClaudeProviderSettingsKey.self)
    }
}
