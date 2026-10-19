import CodexBarCore

@MainActor
final class ClaudeProviderRuntime: ProviderRuntime {
    let id: UsageProvider = .claude
    private var lastSwapConfiguration: Configuration?

    func start(context: ProviderRuntimeContext) {
        self.reconcileSwapConfiguration(context: context)
    }

    func stop(context: ProviderRuntimeContext) {
        self.lastSwapConfiguration = nil
        context.store.clearClaudeSwapAccountState()
    }

    func settingsDidChange(context: ProviderRuntimeContext) {
        self.reconcileSwapConfiguration(context: context)
    }

    private func reconcileSwapConfiguration(context: ProviderRuntimeContext) {
        let configuration = Configuration(
            providerEnabled: context.store.isEnabled(.claude),
            enabled: context.store.providerSourceRoute(for: .claude).isNative && context.settings.claudeSwapEnabled,
            executablePath: context.settings.claudeSwapExecutablePath,
            source: context.settings.claudeSwapSource)
        guard configuration != self.lastSwapConfiguration else { return }
        self.lastSwapConfiguration = configuration
        context.store.clearClaudeSwapAccountState()
        guard configuration.providerEnabled, configuration.enabled, !configuration.executablePath.isEmpty else {
            return
        }
        context.store.scheduleClaudeSwapAccountRefresh()
    }

    private struct Configuration: Equatable {
        let providerEnabled: Bool
        let enabled: Bool
        let executablePath: String
        let source: ClaudeSwapAccountSource
    }
}
