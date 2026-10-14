import Foundation

extension ProviderConfig {
    /// Persisted with the visibility choices so an upgrade or sync cannot reapply the legacy global gate.
    public var claudeResetCreditsVisibilityMigrated: Bool? {
        get { self.extensionValue(forKey: "claudeResetCreditsVisibilityMigrated") }
        set { self.setExtensionValue(newValue, forKey: "claudeResetCreditsVisibilityMigrated") }
    }

    public var claudeWorkspaceSpendEnabled: Bool? {
        get { self.extensionValue(forKey: "claudeWorkspaceSpendEnabled") }
        set { self.setExtensionValue(newValue, forKey: "claudeWorkspaceSpendEnabled") }
    }

    public var claudeSwapEnabled: Bool? {
        get { self.extensionValue(forKey: "claudeSwapEnabled") }
        set { self.setExtensionValue(newValue, forKey: "claudeSwapEnabled") }
    }

    public var claudeSwapShowSingleAccount: Bool? {
        get { self.extensionValue(forKey: "claudeSwapShowSingleAccount") }
        set { self.setExtensionValue(newValue, forKey: "claudeSwapShowSingleAccount") }
    }

    public var claudeSwapExecutablePath: String? {
        get { self.extensionValue(forKey: "claudeSwapExecutablePath") }
        set { self.setExtensionValue(newValue, forKey: "claudeSwapExecutablePath") }
    }

    public var sanitizedClaudeSwapExecutablePath: String? {
        SettingsValue.cleaned(self.claudeSwapExecutablePath)
    }

    /// Machine-local on purpose: the magpie gateway runs on this Mac, so sync payloads never carry these keys.
    public var claudeMagpieEnabled: Bool? {
        get { self.extensionValue(forKey: "claudeMagpieEnabled") }
        set { self.setExtensionValue(newValue, forKey: "claudeMagpieEnabled") }
    }

    public var claudeMagpieQuotasURL: String? {
        get { self.extensionValue(forKey: "claudeMagpieQuotasURL") }
        set { self.setExtensionValue(newValue, forKey: "claudeMagpieQuotasURL") }
    }

    public var sanitizedClaudeMagpieQuotasURL: String? {
        SettingsValue.cleaned(self.claudeMagpieQuotasURL)
    }
}
