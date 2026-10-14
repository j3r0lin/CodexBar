import CodexBarCore
import Foundation

/// The external source that currently owns Claude account cards. magpie and claude-swap are mutually exclusive,
/// so menus, widgets, and the menu bar icon read accounts through this one value instead of either source.
struct ClaudeAccountSource {
    let accounts: [ProviderAccountUsageSnapshot]
    let showSingleAccount: Bool

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
        case ClaudeMagpieAccountProjection.sourceName:
            ClaudeMagpieAccountProjection.ownershipFingerprint(for: account).map { "claude/magpie:\($0)" }
        default:
            nil
        }
    }

    static func widgetLabel(for account: ProviderAccountUsageSnapshot, in accounts: [ProviderAccountUsageSnapshot])
        -> String
    {
        // claude-swap slots are already privacy-safe ordinals; magpie IDs carry the email.
        if account.id.source == ClaudeSwapAccountProjection.sourceName {
            return "Account \(account.id.opaqueID)"
        }
        let ordinal = (accounts.firstIndex(where: { $0.id == account.id }) ?? 0) + 1
        return "Account \(ordinal)"
    }
}

extension UsageStore {
    var claudeAccountSource: ClaudeAccountSource {
        if self.settings.claudeMagpieEnabled {
            // magpie replaces the ambient account entirely, so even one account is shown as a card.
            return ClaudeAccountSource(accounts: self.claudeMagpieAccountSnapshots, showSingleAccount: true)
        }
        return ClaudeAccountSource(
            accounts: self.claudeSwapAccountSnapshots,
            showSingleAccount: self.settings.claudeSwapShowSingleAccount)
    }

    /// Whether a Claude account source is switched on, so widgets drop its accounts as soon as it is turned off.
    var claudeAccountSourceEnabled: Bool {
        self.settings.claudeMagpieEnabled || self.settings.claudeSwapEnabled
    }

    func shouldFetchClaudeMagpieAccounts() -> Bool {
        self.isEnabled(.claude) && self.settings.claudeMagpieEnabled
    }

    func clearClaudeMagpieAccountState() {
        let hadState = !self.claudeMagpieAccountSnapshots.isEmpty ||
            self.claudeMagpieLastRefreshAt != nil || self.claudeMagpieLastError != nil
        self.claudeMagpieRefreshTask?.cancel()
        self.claudeMagpieRefreshTask = nil
        self.claudeMagpieAccountSnapshots = []
        self.claudeMagpieLastRefreshAt = nil
        self.claudeMagpieLastError = nil
        if hadState {
            self.claudeMagpieRevision &+= 1
            self.persistWidgetSnapshot(reason: "claude-magpie-accounts")
        }
    }

    /// Removes the ambient Claude usage so no surface keeps showing a credential-derived snapshot under magpie.
    func clearClaudeAmbientUsageForMagpie() {
        let instanceID = UsageProvider.claude.instanceID
        self.snapshots.removeValue(forKey: instanceID)
        self.errors[instanceID] = nil
        self.diagnostics[instanceID] = nil
        self.lastSourceLabels.removeValue(forKey: instanceID)
        self.lastFetchAttempts.removeValue(forKey: instanceID)
        self.accountSnapshots.removeValue(forKey: instanceID)
    }

    func scheduleClaudeMagpieAccountRefresh(generation: UInt64? = nil) {
        self.claudeMagpieRefreshTask?.cancel()
        guard self.shouldFetchClaudeMagpieAccounts() else {
            self.clearClaudeMagpieAccountState()
            return
        }
        self.claudeMagpieRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshClaudeMagpieAccounts(generation: generation)
        }
    }

    func refreshClaudeMagpieAccounts(generation: UInt64? = nil) async {
        let quotasURL = self.settings.claudeMagpieQuotasURL
        do {
            let snapshots = try await ClaudeMagpieAccountReader.readAccounts(
                quotasURL: quotasURL,
                transport: self.claudeMagpieTransport)
            guard self.isCurrentClaudeMagpieRefresh(quotasURL: quotasURL, generation: generation) else { return }
            self.claudeMagpieAccountSnapshots = snapshots
            self.claudeMagpieLastRefreshAt = Date()
            self.claudeMagpieLastError = nil
            self.claudeMagpieRevision &+= 1
            self.persistWidgetSnapshot(reason: "claude-magpie-accounts")
        } catch is CancellationError {
            return
        } catch {
            guard self.isCurrentClaudeMagpieRefresh(quotasURL: quotasURL, generation: generation) else { return }
            // Keep the last successful accounts as stale data; the settings pane shows the error.
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if self.claudeMagpieLastError != message {
                self.claudeMagpieLastError = message
                self.claudeMagpieRevision &+= 1
            }
        }
    }

    private func isCurrentClaudeMagpieRefresh(quotasURL: String, generation: UInt64?) -> Bool {
        !Task.isCancelled &&
            self.isCurrentProviderRefreshGeneration(.claude, generation: generation) &&
            self.shouldFetchClaudeMagpieAccounts() &&
            self.settings.claudeMagpieQuotasURL == quotasURL
    }
}
