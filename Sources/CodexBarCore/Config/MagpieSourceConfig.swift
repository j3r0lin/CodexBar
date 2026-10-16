import Foundation

/// Top-level magpie unified-source configuration. While enabled, every provider the gateway
/// reports is read from magpie only — CodexBar never touches that provider's local credentials,
/// Keychain items, browser cookies, CLIs, or local databases, and cost/credits/history surfaces
/// stay empty for it rather than showing stale or zero values.
public struct MagpieSourceConfig: Codable, Sendable, Equatable {
    public var enabled: Bool?
    public var quotasURL: String?

    public init(enabled: Bool? = nil, quotasURL: String? = nil) {
        self.enabled = enabled
        self.quotasURL = quotasURL
    }

    public var sanitizedQuotasURL: String? {
        SettingsValue.cleaned(self.quotasURL)
    }

    /// Legacy Claude-only keys migrated into this config. Migration runs only when the legacy
    /// switch was explicitly on; an explicit off stays off by simply not creating the config.
    static func migrating(from providers: [ProviderConfig]) -> MagpieSourceConfig? {
        guard let claude = providers.first(where: { $0.id.firstPartyProvider == .claude }),
              claude.claudeMagpieEnabled == true
        else { return nil }
        return MagpieSourceConfig(enabled: true, quotasURL: claude.sanitizedClaudeMagpieQuotasURL)
    }

    /// Removes the legacy Claude-scoped keys so saves write only the new top-level config.
    static func stripLegacyKeys(from providers: inout [ProviderConfig]) {
        for index in providers.indices where providers[index].id.firstPartyProvider == .claude {
            providers[index].claudeMagpieEnabled = nil
            providers[index].claudeMagpieQuotasURL = nil
        }
    }
}
