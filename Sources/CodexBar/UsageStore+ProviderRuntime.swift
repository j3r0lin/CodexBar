import CodexBarCore

extension UsageStore {
    func performRuntimeAction(_ action: ProviderRuntimeAction, for provider: UsageProvider) async {
        guard self.providerSourceRoute(for: provider).isNative else { return }
        guard let runtime = self.providerRuntimes[provider.instanceID] else { return }
        let context = ProviderRuntimeContext(provider: provider, settings: self.settings, store: self)
        await runtime.perform(action: action, context: context)
    }

    func updateProviderRuntimes() {
        self.reconcileMagpieSourceConfiguration()
        for (instanceID, runtime) in self.providerRuntimes {
            guard let provider = instanceID.firstPartyProvider else { continue }
            let context = ProviderRuntimeContext(provider: provider, settings: self.settings, store: self)
            if self.isEnabled(provider) {
                runtime.start(context: context)
            } else {
                runtime.stop(context: context)
            }
            runtime.settingsDidChange(context: context)
        }
    }
}
