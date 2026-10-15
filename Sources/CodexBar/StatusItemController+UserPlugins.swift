#if canImport(JavaScriptCore)
import AppKit
import CodexBarCore
import SwiftUI

extension StatusItemController {
    var shouldMergeIcons: Bool {
        self.settings.mergeIcons && (
            self.store.enabledProvidersForDisplay().count > 1 ||
                !self.topLevelUserProviderPlugins().isEmpty)
    }

    func topLevelUserProviderPlugins() -> [UserProviderPlugin] {
        UserProviderPluginRegistry.all.filter {
            $0.manifest.topLevel && self.settings.isPluginEnabled($0.manifest.id)
        }
    }

    func switcherProviderIDs(enabledFirstPartyProviders: [UsageProvider]) -> [ProviderInstanceID] {
        enabledFirstPartyProviders.map(\.instanceID) + self.topLevelUserProviderPlugins().map(\.manifest.id)
    }

    /// The merged menu always shows Overview; provider details open as submenus off its rows.
    var mergedMenuSelection: ProviderSwitcherSelection? {
        self.shouldMergeIcons ? .overview : nil
    }

    func addUserPluginMenuCards(
        to menu: NSMenu,
        width: CGFloat,
        selectedPluginID: ProviderInstanceID? = nil)
    {
        let hasTopLevelSwitcher = self.shouldMergeIcons &&
            self.switcherProviderIDs(
                enabledFirstPartyProviders: self.store.enabledFirstPartyProvidersForDisplay()).count > 1
        let plugins = Self.userPluginsForMenu(
            UserProviderPluginRegistry.all,
            isEnabled: self.settings.isPluginEnabled,
            topLevelSwitcherVisible: hasTopLevelSwitcher,
            selectedPluginID: selectedPluginID)
        guard !plugins.isEmpty else { return }
        if !menu.items.isEmpty, menu.items.last?.isSeparatorItem != true {
            menu.addItem(.separator())
        }
        for (index, plugin) in plugins.enumerated() {
            let snapshot = self.store.snapshots[plugin.manifest.id]
            let error = self.store.errors[plugin.manifest.id]
            let view = UserPluginMenuCardView(
                plugin: plugin,
                snapshot: snapshot,
                error: error,
                isRefreshing: self.store.refreshingProviders.contains(plugin.manifest.id),
                showUsed: self.settings.usageBarsShowUsed,
                width: width,
                onRefresh: { [weak self] in
                    self?.startManualRefresh(
                        for: plugin.manifest.id,
                        originatingMenuID: nil,
                        originatingMenuInteractionGeneration: nil)
                })
            menu.addItem(self.makeMenuCardItem(
                view,
                id: "pluginCard:\(plugin.manifest.id.rawValue)",
                width: width,
                heightCacheScope: plugin.manifest.id.rawValue,
                heightCacheFingerprint: UserPluginMenuCardView.fingerprint(snapshot: snapshot, error: error),
                containsInteractiveControls: true))
            if index < plugins.count - 1 {
                menu.addItem(.separator())
            }
        }
        menu.addItem(.separator())
    }

    func refreshOpenMenusAfterUserPluginRefresh(_ instanceID: ProviderInstanceID) {
        self.invalidateMenus()
        guard self.isMenuRefreshEnabled else { return }
        let cardID = "pluginCard:\(instanceID.rawValue)"
        // Plugin cards capture snapshots, so their visible payload needs the guarded rebuild path.
        for menu in self.openMenus.values
            where menu.items.contains(where: { $0.representedObject as? String == cardID })
        {
            self.scheduleOpenMenuRebuildIfStillVisible(menu, provider: self.menuProvider(for: menu))
        }
    }

    static func userPluginsForMenu(
        _ plugins: [UserProviderPlugin],
        isEnabled: (ProviderInstanceID) -> Bool,
        topLevelSwitcherVisible: Bool,
        selectedPluginID: ProviderInstanceID?) -> [UserProviderPlugin]
    {
        let enabledPlugins = plugins.filter { isEnabled($0.manifest.id) }
        if let selectedPluginID {
            let selected = enabledPlugins.filter { $0.manifest.id == selectedPluginID }
            let legacy = enabledPlugins.filter {
                !$0.manifest.topLevel && $0.manifest.id != selectedPluginID
            }
            return selected + legacy
        }
        return enabledPlugins.filter { !topLevelSwitcherVisible || !$0.manifest.topLevel }
    }
}

struct UserPluginQuotaPresentation: Equatable {
    let percent: Double
    let text: String

    static func make(usedPercent: Double, showUsed: Bool) -> Self {
        let used = min(100, max(0, usedPercent))
        let remaining = 100 - used
        return Self(
            percent: showUsed ? used : remaining,
            text: UsageFormatter.usageLine(remaining: remaining, used: used, showUsed: showUsed))
    }
}

private struct UserPluginMenuCardView: View {
    let plugin: UserProviderPlugin
    let snapshot: UsageSnapshot?
    let error: String?
    let isRefreshing: Bool
    let showUsed: Bool
    let width: CGFloat
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(self.plugin.manifest.icon.monogram)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(self.tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(self.plugin.manifest.name).font(.headline)
                    Text(self.plugin.fileURL.lastPathComponent)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if self.isRefreshing {
                    ProgressView().controlSize(.small)
                } else {
                    Button(action: self.onRefresh) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help(L("Refresh"))
                }
            }
            if let snapshot {
                self.window("Primary", snapshot.primary)
                self.window("Secondary", snapshot.secondary)
                self.window("Tertiary", snapshot.tertiary)
                if let cost = snapshot.providerCost {
                    HStack {
                        Text(cost.period ?? "Cost").foregroundStyle(.secondary)
                        Spacer()
                        Text(UsageFormatter.currencyString(cost.used, currencyCode: cost.currencyCode))
                            .fontWeight(.medium)
                    }
                    .font(.caption)
                }
                if !snapshot.details.isEmpty {
                    Divider()
                    ProviderDetailSectionsContent(sections: snapshot.details, chartColor: self.tint)
                }
                if let identity = snapshot.identity(for: self.plugin.manifest.id) {
                    self.identity(identity)
                }
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            } else {
                Text(L("No usage fetched yet")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, UsageMenuCardLayout.horizontalPadding)
        .padding(.vertical, 8)
        .frame(width: self.width, alignment: .leading)
    }

    @ViewBuilder
    private func identity(_ identity: ProviderIdentitySnapshot) -> some View {
        if identity.accountEmail != nil || identity.accountOrganization != nil || identity.loginMethod != nil
            || identity.accountID != nil
        {
            Divider()
            self.identityRow("Account", identity.accountEmail)
            self.identityRow("Organization", identity.accountOrganization)
            self.identityRow("Plan", identity.loginMethod)
            self.identityRow("Account ID", identity.accountID)
        }
    }

    @ViewBuilder
    private func identityRow(_ label: String, _ value: String?) -> some View {
        if let value {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(value).fontWeight(.medium).textSelection(.enabled)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func window(_ title: String, _ window: RateWindow?) -> some View {
        if let window {
            let presentation = UserPluginQuotaPresentation.make(
                usedPercent: window.usedPercent,
                showUsed: self.showUsed)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).foregroundStyle(.secondary)
                    Spacer()
                    Text(presentation.text).monospacedDigit()
                }
                .font(.caption)
                UsageProgressBar(
                    percent: presentation.percent,
                    tint: self.tint,
                    accessibilityLabel: "\(title) usage")
            }
        }
    }

    private var tint: Color {
        let raw = self.plugin.manifest.icon.tint.dropFirst()
        let value = UInt32(raw, radix: 16) ?? 0x6B7280
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }

    static func fingerprint(snapshot: UsageSnapshot?, error: String?) -> String {
        [
            snapshot?.updatedAt.timeIntervalSinceReferenceDate.description ?? "none",
            String(snapshot?.details.count ?? 0),
            error ?? "",
        ].joined(separator: "|")
    }
}
#endif
