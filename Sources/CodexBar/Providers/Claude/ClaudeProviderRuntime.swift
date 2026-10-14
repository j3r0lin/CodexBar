import CodexBarCore

@MainActor
final class ClaudeProviderRuntime: ProviderRuntime {
    let id: UsageProvider = .claude
    private var lastSwapConfiguration: Configuration?
    private var lastMagpieConfiguration: MagpieConfiguration?

    func start(context: ProviderRuntimeContext) {
        self.reconcileSwapConfiguration(context: context)
    }

    func stop(context: ProviderRuntimeContext) {
        self.lastSwapConfiguration = nil
        self.lastMagpieConfiguration = nil
        context.store.clearClaudeSwapAccountState()
        context.store.clearClaudeMagpieAccountState()
    }

    func settingsDidChange(context: ProviderRuntimeContext) {
        self.reconcileSwapConfiguration(context: context)
    }

    private func reconcileMagpieConfiguration(context: ProviderRuntimeContext) {
        let configuration = MagpieConfiguration(
            providerEnabled: context.store.isEnabled(.claude),
            enabled: context.settings.claudeMagpieEnabled,
            quotasURL: context.settings.claudeMagpieQuotasURL)
        guard configuration != self.lastMagpieConfiguration else { return }
        let wasEnabled = self.lastMagpieConfiguration?.enabled ?? false
        self.lastMagpieConfiguration = configuration

        context.store.clearClaudeMagpieAccountState()
        if configuration.providerEnabled, configuration.enabled {
            // Drop whatever the ambient Claude Code credential fetch published; magpie now owns Claude.
            context.store.clearClaudeAmbientUsageForMagpie()
            context.store.scheduleClaudeMagpieAccountRefresh()
        } else if wasEnabled, configuration.providerEnabled {
            Task { await context.store.refreshProvider(.claude) }
        }
    }

    private func reconcileSwapConfiguration(context: ProviderRuntimeContext) {
        self.reconcileMagpieConfiguration(context: context)
        let configuration = Configuration(
            providerEnabled: context.store.isEnabled(.claude),
            enabled: context.settings.claudeSwapEffectivelyEnabled,
            executablePath: context.settings.claudeSwapExecutablePath)
        guard configuration != self.lastSwapConfiguration else { return }
        self.lastSwapConfiguration = configuration

        // Cancel before clearing so an old executable can never repopulate the menu.
        context.store.clearClaudeSwapAccountState()
        guard configuration.providerEnabled, configuration.enabled, !configuration.executablePath.isEmpty else {
            return
        }
        context.store.scheduleClaudeSwapAccountRefresh()
    }

    private struct MagpieConfiguration: Equatable {
        let providerEnabled: Bool
        let enabled: Bool
        let quotasURL: String
    }

    private struct Configuration: Equatable {
        let providerEnabled: Bool
        let enabled: Bool
        let executablePath: String
    }
}
