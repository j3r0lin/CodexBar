import CodexBarCore
import Foundation

extension SettingsStore {
    /// The magpie unified-source switch. While on, every provider the gateway reports is read
    /// from magpie only; taken-over providers never touch local credentials, cookies, CLIs, or
    /// databases, and show no cost, credits, or history. Migrating from the legacy Claude-only
    /// switch widens ownership to every magpie provider.
    var magpieSourceEnabled: Bool {
        get { self.configSnapshot.magpie?.enabled ?? false }
        set {
            self.updateConfig(reason: "magpie-source", affectsBackgroundWork: true) { config in
                var magpie = config.magpie ?? MagpieSourceConfig()
                magpie.enabled = newValue
                config.magpie = magpie
                MagpieSourceConfig.stripLegacyKeys(from: &config.providers)
            }
            CodexBarLog.logger(LogCategories.settings).info(
                "Provider mode updated",
                metadata: ["provider": "magpie", "field": "magpieSourceEnabled", "value": String(newValue)])
        }
    }

    /// Empty means `MagpieQuotasReader.defaultQuotasURL`.
    var magpieQuotasURL: String {
        get { self.configSnapshot.magpie?.sanitizedQuotasURL ?? "" }
        set {
            self.updateConfig(reason: "magpie-source", affectsBackgroundWork: true) { config in
                var magpie = config.magpie ?? MagpieSourceConfig()
                magpie.quotasURL = self.normalizedConfigValue(newValue)
                config.magpie = magpie
            }
            CodexBarLog.logger(LogCategories.settings).info(
                "Provider mode updated",
                metadata: [
                    "provider": "magpie",
                    "field": "magpieQuotasURL",
                    "value": newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "cleared" : "set",
                ])
        }
    }

    var magpieTakeoverWireIDs: Set<String> {
        get { Set(self.userDefaults.stringArray(forKey: "magpieTakeoverProviderIDs") ?? []) }
        set { self.userDefaults.set(newValue.sorted(), forKey: "magpieTakeoverProviderIDs") }
    }
}
