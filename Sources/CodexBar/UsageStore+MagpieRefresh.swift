import CodexBarCore
import Foundation

/// The external source that currently owns Claude account cards. magpie and claude-swap are mutually exclusive,
/// so menus, widgets, and the menu bar icon read accounts through this one value instead of either source.
struct ClaudeAccountSource {
    let accounts: [ProviderAccountUsageSnapshot]
    let showSingleAccount: Bool
    /// The source's last refresh error while its accounts are retained from an earlier success.
    let lastError: String?

    /// Whether these accounts replace the ambient and token-account Claude presentation.
    var ownsPresentation: Bool {
        ClaudeSwapAccountProjection.shouldPresentAccounts(
            accountCount: self.accounts.count,
            showSingleAccount: self.showSingleAccount)
    }

    var activeAccount: ProviderAccountUsageSnapshot? {
        self.accounts.first(where: \.isActive)
    }

    /// Persisted widget identity; never contains the account's email, organization, or label.
    static func widgetOwnerKey(for account: ProviderAccountUsageSnapshot) -> String? {
        switch account.id.source {
        case ClaudeSwapAccountProjection.sourceName:
            ClaudeSwapRetainedUsageStore.ownershipFingerprint(for: account)
                .map { "claude/swap:\(account.id.opaqueID):\($0)" }
        case MagpieAccountProjection.sourceName:
            // magpie opaque IDs are already opaque fingerprints of (provider, email, organization).
            "claude/magpie:\(account.id.opaqueID)"
        default:
            nil
        }
    }

    static func widgetLabel(for account: ProviderAccountUsageSnapshot, in accounts: [ProviderAccountUsageSnapshot])
        -> String
    {
        // claude-swap slots are already privacy-safe ordinals; magpie rows use their per-provider ordinal.
        if account.id.source == ClaudeSwapAccountProjection.sourceName {
            return "Account \(account.id.opaqueID)"
        }
        let ordinal = account.sourceOrdinal ?? (accounts.firstIndex(where: { $0.id == account.id }) ?? 0) + 1
        return "Account \(ordinal)"
    }
}

extension UsageStore {
    // MARK: - Source routing

    /// Where a provider's reads come from right now. Evaluated at the front of every read path so
    /// a magpie-owned provider never touches local credentials, files, cookies, or processes.
    func providerSourceRoute(for provider: UsageProvider) -> ProviderSourceRoute {
        ProviderSourceRoute.resolve(
            provider: provider,
            enabled: self.settings.magpieSourceEnabled,
            ownedWireIDs: self.magpieTakeoverWireIDs,
            discoverySucceeded: self.magpieDiscoveryCompleted && self.magpieLastRefreshAt != nil)
    }

    /// OpenAI dashboard, reset credits and weekly history belong to native Codex only.
    var canReadNativeCodexSource: Bool {
        // Provider-specific by design: these Codex-only entry points share the same source route.
        self.providerSourceRoute(for: .codex).isNative
    }

    /// Wire IDs magpie owns on this Mac: the persisted takeover set plus everything the latest
    /// response reported. The set only grows while the switch is on; turning the switch off
    /// clears it and returns providers to their native sources.
    var magpieTakeoverWireIDs: Set<String> {
        var ids = self.settings.magpieTakeoverWireIDs
        ids.formUnion(self.magpieAccountSnapshots.map(\.provider.wireID))
        return ids
    }

    /// magpie providers for the Overview: every account row from the latest response. Providers
    /// with no windows and no error are not shown.
    var magpieOverviewSnapshots: [MagpieAccountSnapshot] {
        self.magpieAccountSnapshots.filter { !$0.windows.isEmpty || $0.error != nil }
    }

    // MARK: - Claude account source (menus, widgets)

    var claudeAccountSource: ClaudeAccountSource {
        if self.settings.magpieSourceEnabled {
            // magpie replaces the ambient account entirely, so even one account is shown as a card.
            return ClaudeAccountSource(
                // Provider-specific by design: the Claude account bridge also serves claude-swap consumers.
                accounts: MagpieUsageProjection.providerAccountSnapshots(
                    for: .claude,
                    in: self.magpieAccountSnapshots),
                showSingleAccount: true,
                lastError: self.magpieLastError)
        }
        return ClaudeAccountSource(
            accounts: self.claudeSwapAccountSnapshots,
            showSingleAccount: self.settings.claudeSwapShowSingleAccount,
            lastError: self.claudeSwapLastError)
    }

    /// Whether a Claude account source is switched on, so widgets drop its accounts as soon as it is turned off.
    var claudeAccountSourceEnabled: Bool {
        self.settings.magpieSourceEnabled || self.settings.claudeSwapEnabled
    }

    /// Replaces the provider debug log while magpie owns the provider, so the log never probes
    /// credentials, the Keychain, browser cookies, or provider CLIs. Nil for native providers.
    func magpieDebugNote(for provider: UsageProvider) -> String? {
        let route = self.providerSourceRoute(for: provider)
        let reference: MagpieProviderReference
        switch route {
        case .native:
            return nil
        case let .magpie(owned):
            reference = owned
        case .magpieSuspended:
            return self.magpieSuspendedNote(for: provider)
        case .waitingForMagpieDiscovery:
            reference = MagpieProviderMapping.reference(
                for: MagpieProviderMapping.wireID(for: provider) ?? provider.rawValue)
        }
        let url = self.settings.magpieQuotasURL.isEmpty
            ? MagpieQuotasReader.defaultQuotasURL
            : self.settings.magpieQuotasURL
        let state = switch route {
        case .native: "native"
        case .magpie: "owned by magpie"
        case .magpieSuspended: "suspended while the magpie source is on"
        case .waitingForMagpieDiscovery: "waiting for first magpie discovery"
        }
        return [
            "magpie owns \(reference.displayName) usage; local credential and process reads are skipped.",
            "magpie URL: \(url)",
            "Route: \(state)",
            "Last magpie error: \(self.magpieLastError ?? "none")",
        ].joined(separator: "\n")
    }

    // MARK: - Refresh

    func shouldFetchMagpieAccounts() -> Bool {
        self.settings.magpieSourceEnabled
    }

    func clearMagpieAccountState() {
        let hadState = !self.magpieAccountSnapshots.isEmpty ||
            self.magpieLastRefreshAt != nil || self.magpieLastError != nil || self.magpieDiscoveryCompleted
        self.magpieRefreshEpoch &+= 1
        self.magpieRefreshTask?.cancel()
        self.magpieRefreshTask = nil
        self.magpieRefreshInFlight = false
        for (wireID, provider) in MagpieProviderMapping.nativeProviders {
            guard self.magpieTakeoverWireIDs.contains(wireID),
                  self.lastSourceLabels[provider.instanceID] == MagpieAccountProjection.sourceLabel
            else { continue }
            self.snapshots.removeValue(forKey: provider.instanceID)
            self.errors.removeValue(forKey: provider.instanceID)
            self.lastSourceLabels.removeValue(forKey: provider.instanceID)
        }
        self.magpieAccountSnapshots = []
        self.magpieLastRefreshAt = nil
        self.magpieLastError = nil
        self.magpieDiscoveryCompleted = false
        if hadState {
            self.magpieRevision &+= 1
            self.persistWidgetSnapshot(reason: "magpie-accounts")
        }
    }

    /// Starts the next refresh round when no request is in flight. The fetch itself is single-flight:
    /// concurrent provider passes in one refresh round share the same GET.
    func scheduleMagpieAccountRefresh(generation: UInt64? = nil) {
        if let task = self.magpieRefreshTask, !task.isCancelled, self.magpieRefreshInFlight { return }
        self.magpieRefreshTask = nil
        guard self.shouldFetchMagpieAccounts() else {
            self.clearMagpieAccountState()
            return
        }
        let epoch = self.magpieRefreshEpoch
        self.magpieRefreshInFlight = true
        self.magpieRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performMagpieRefresh(generation: generation, epoch: epoch)
        }
    }

    /// Awaits the shared magpie refresh so a managed provider's refresh pass completes only after
    /// magpie data (or its error) has landed.
    func awaitMagpieRefresh(generation: UInt64? = nil) async {
        if let task = self.magpieRefreshTask, !task.isCancelled {
            await task.value
            return
        }
        guard self.shouldFetchMagpieAccounts() else { return }
        let epoch = self.magpieRefreshEpoch
        self.magpieRefreshInFlight = true
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performMagpieRefresh(generation: generation, epoch: epoch)
        }
        self.magpieRefreshTask = task
        await task.value
    }

    func refreshMagpieAccounts(generation: UInt64? = nil) async {
        self.scheduleMagpieAccountRefresh(generation: generation)
        await self.awaitMagpieRefresh(generation: generation)
    }

    private func performMagpieRefresh(generation: UInt64?, epoch: UInt64) async {
        defer {
            if epoch == self.magpieRefreshEpoch {
                self.magpieRefreshInFlight = false
            }
        }
        let quotasURL = self.settings.magpieQuotasURL
        do {
            let rows = try await MagpieQuotasReader.readRows(
                quotasURL: quotasURL,
                transport: self.magpieTransport)
            guard self.isCurrentMagpieRefresh(quotasURL: quotasURL, epoch: epoch) else { return }
            let incoming = MagpieAccountProjection.snapshots(from: rows)
            var snapshots = incoming
            var retainedProviders: [String] = []
            // Retention groups by native provider: fresh rows under any wire ID of a provider
            // retire the retained rows of every wire ID of that provider, so a wire-ID rename
            // never leaves a stale last-known card behind. Unknown providers group by wire ID.
            func retentionKey(of account: MagpieAccountSnapshot) -> String {
                account.provider.nativeProvider.map { "native:\($0.rawValue)" }
                    ?? "wire:\(account.provider.wireID)"
            }
            for key in Set(self.magpieAccountSnapshots.map(retentionKey)) {
                let previous = self.magpieAccountSnapshots.filter {
                    retentionKey(of: $0) == key && !$0.windows.isEmpty &&
                        $0.error != MagpieAccountProjection.unstableIdentityError
                }
                let current = incoming.filter { retentionKey(of: $0) == key }
                guard !previous.isEmpty else { continue }
                if current.isEmpty {
                    let label = previous.first.map {
                        $0.provider.nativeProvider?.rawValue ?? $0.provider.wireID
                    } ?? key
                    let message = "magpie returned no usable quota rows for \(label)."
                    snapshots.append(contentsOf: previous.map { $0.retainedAsLastKnown(error: message) })
                    retainedProviders.append(label)
                } else {
                    snapshots = snapshots.map { account in
                        guard retentionKey(of: account) == key, account.windows.isEmpty,
                              let prior = previous.first(where: { $0.id == account.id })
                        else { return account }
                        return prior.retainedAsLastKnown(error: account.error)
                    }
                }
            }
            self.magpieDiscoveryCompleted = true
            self.magpieAccountSnapshots = snapshots
            self.magpieLastRefreshAt = Date()
            self.magpieLastError = retainedProviders.isEmpty
                ? nil : "magpie returned no usable rows: \(retainedProviders.sorted().joined(separator: ", "))."
            // The takeover set only grows while the switch is on: a provider that disappears from
            // a later response stays magpie-owned instead of resuming native reads.
            var takeover = self.settings.magpieTakeoverWireIDs
            takeover.formUnion(rows.map(\.provider))
            if takeover != self.settings.magpieTakeoverWireIDs {
                self.settings.magpieTakeoverWireIDs = takeover
            }
            if self.canReadNativeCodexSource, self.codexAccountSnapshots.isEmpty,
               let snapshotStore = self.codexAccountUsageSnapshotStore
            {
                self.codexAccountSnapshots = snapshotStore.load(
                    for: self.freshCodexVisibleAccountsForSnapshotHydration())
            }
            self.publishMagpieAmbientSnapshots(error: nil)
            self.magpieRevision &+= 1
            self.persistWidgetSnapshot(reason: "magpie-accounts")
        } catch is CancellationError {
            return
        } catch {
            guard self.isCurrentMagpieRefresh(quotasURL: quotasURL, epoch: epoch) else { return }
            // A finished attempt ends the waiting state even when it fails: managed providers show
            // the gateway error instead of reading credentials.
            self.magpieDiscoveryCompleted = true
            // Keep the last successful accounts, but as last-known usage so age-less surfaces stop
            // presenting them as current; cards and settings show the error.
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let retained = self.magpieAccountSnapshots.filter {
                $0.error != MagpieAccountProjection.unstableIdentityError
            }.map {
                $0.usesLastKnownUsage ? $0 : $0.retainedAsLastKnown(error: "magpie refresh failed: \(message)")
            }
            self.magpieAccountSnapshots = retained
            self.magpieLastError = message
            self.publishMagpieAmbientSnapshots(error: message)
            self.magpieRevision &+= 1
        }
    }

    /// User-facing message for a Claude-family provider the switch suspends without magpie data.
    static func magpieSuspendedMessage(for provider: UsageProvider) -> String {
        ProviderSourceRoute.suspendedMessage(for: provider)
    }

    private func magpieSuspendedNote(for provider: UsageProvider) -> String {
        let url = self.settings.magpieQuotasURL.isEmpty
            ? MagpieQuotasReader.defaultQuotasURL
            : self.settings.magpieQuotasURL
        return [
            Self.magpieSuspendedMessage(for: provider)
                + " Local credential and process reads are skipped.",
            "magpie URL: \(url)",
            "Route: suspended while the magpie source is on",
            "Last magpie error: \(self.magpieLastError ?? "none")",
        ].joined(separator: "\n")
    }

    /// Publishes the active magpie account's usage as each managed native provider's ambient
    /// snapshot, so the menu bar icon, widgets, and detail cards keep working without any
    /// credential-derived fetch. Disabled providers keep their rows only in the Overview list.
    private func publishMagpieAmbientSnapshots(error: String?) {
        for (wireID, provider) in MagpieProviderMapping.nativeProviders {
            guard self.magpieTakeoverWireIDs.contains(wireID) else { continue }
            guard self.isEnabled(provider) else { continue }
            let accounts = MagpieUsageProjection.providerAccountSnapshots(
                for: provider, in: self.magpieAccountSnapshots)
            let active = accounts.first(where: \.isActive)
            if let usage = active?.snapshot {
                self.snapshots[provider.instanceID] = usage
                self.errors[provider.instanceID] = nil
                self.lastSourceLabels[provider.instanceID] = MagpieAccountProjection.sourceLabel
            } else {
                // A vanished provider keeps no ambient snapshot; the takeover boundary remains.
                self.snapshots.removeValue(forKey: provider.instanceID)
                if let error {
                    self.errors[provider.instanceID] = "magpie: \(error)"
                } else if let accountError = active?.error {
                    self.errors[provider.instanceID] = accountError
                }
            }
        }
        // Claude-family providers the switch suspends without any magpie data never fall back to
        // native reads: keep any last-known snapshot, otherwise show the suspended state.
        for provider in ProviderSourceRoute.switchOnNativeForbidden {
            guard self.isEnabled(provider),
                  self.providerSourceRoute(for: provider) == .magpieSuspended
            else { continue }
            if self.snapshots[provider.instanceID] == nil {
                self.errors[provider.instanceID] = Self.magpieSuspendedMessage(for: provider)
            }
        }
    }

    private func isCurrentMagpieRefresh(quotasURL: String, epoch: UInt64) -> Bool {
        !Task.isCancelled &&
            epoch == self.magpieRefreshEpoch &&
            self.shouldFetchMagpieAccounts() &&
            self.settings.magpieQuotasURL == quotasURL
    }

    // MARK: - Switch reconciliation (moved up from the Claude provider runtime)

    /// Applies magpie switch and URL changes: on enable, cancel in-flight native work for every
    /// known-mapped provider and clear its credential-derived display state before the first
    /// discovery; on disable, clear magpie state and return providers to their native sources.
    func reconcileMagpieSourceConfiguration() {
        let configuration = (
            enabled: self.settings.magpieSourceEnabled,
            quotasURL: self.settings.magpieQuotasURL)
        if let last = self.lastMagpieSourceConfiguration,
           last.enabled == configuration.enabled, last.quotasURL == configuration.quotasURL
        {
            return
        }
        let previous = self.lastMagpieSourceConfiguration
        self.lastMagpieSourceConfiguration = configuration
        // A provider with two wire IDs (Grok) appears once; the Set keeps its clears single.
        let mappedProviders = Set(MagpieProviderMapping.nativeProviders.values)
        // The Claude family is switch-suspended even without a magpie wire ID, so it gets the
        // same cleanup and refresh treatment as mapped providers.
        let gatedProviders = mappedProviders.union(ProviderSourceRoute.switchOnNativeForbidden)

        if configuration.enabled {
            self.clearMagpieAccountState()
            for provider in gatedProviders {
                self.invalidateProviderRefreshRequests(provider)
                self.clearCredentialDerivedStateForMagpie(provider)
            }
            self.scheduleMagpieAccountRefresh()
        } else {
            self.clearMagpieAccountState()
            self.settings.magpieTakeoverWireIDs = []
            for provider in ProviderSourceRoute.switchOnNativeForbidden {
                if self.errors[provider.instanceID] == Self.magpieSuspendedMessage(for: provider) {
                    self.errors.removeValue(forKey: provider.instanceID)
                }
            }
            guard previous?.enabled == true else { return }
            for provider in gatedProviders where self.isEnabled(provider) {
                Task { await self.refreshProvider(provider) }
            }
        }
    }

    /// Removes everything a native read published for a provider about to be magpie-owned:
    /// ambient usage, account snapshots, diagnostics, token cost, and Codex credits/dashboard
    /// state. Disk-backed user data is never touched.
    func clearCredentialDerivedStateForMagpie(_ provider: UsageProvider) {
        // Provider-specific by design: Claude and Codex own additional credential-derived caches to clear.
        if provider == .claude {
            // Same coverage as a credential swap, including local token cost.
            self.clearClaudeCredentialDerivedStateForCredentialSwap(keepsLocalTokenCost: false)
        }
        self.clearProviderRuntimeState(provider)
        if provider == .codex {
            self.cancelScheduledCreditsRefresh()
            self.cancelCodexPlanHistoryBackfill()
            self.invalidateOpenAIDashboardRefreshTask()
            self.codexAccountSnapshots = []
            self.credits = nil
            self.lastCreditsError = nil
            self.lastCreditsSnapshot = nil
            self.lastCreditsSnapshotAccountKey = nil
            self.openAIDashboard = nil
            self.lastOpenAIDashboardError = nil
            self.openAIDashboardRequiresLogin = false
            self.lastOpenAIDashboardSnapshot = nil
            self.codexHistoricalDataset = nil
            self.codexHistoricalDatasetAccountKey = nil
            self.historicalPaceRevision &+= 1
        }
        // Plan history stays in the persisted dictionary (saving it would delete the file); the
        // read and write paths skip it while magpie owns the provider.
        self.planUtilizationHistoryRevision &+= 1
        self.diagnostics[provider.instanceID] = nil
        self.lastFetchAttempts.removeValue(forKey: provider.instanceID)
        self.accountSnapshots.removeValue(forKey: provider.instanceID)
    }
}
