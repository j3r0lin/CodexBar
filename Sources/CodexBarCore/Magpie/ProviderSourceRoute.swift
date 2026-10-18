import Foundation

/// Where a provider's usage data comes from while the magpie unified source switch is on.
///
/// Evaluated at the very front of every read path (refresh, settings status, debug log, token
/// cost, CLI). `waitingForMagpieDiscovery` holds native reads until the first discovery attempt
/// finishes, so enabling the switch never races a credential read; a failed first discovery
/// shows the gateway error instead of falling back to native reads.
public enum ProviderSourceRoute: Sendable, Equatable {
    case waitingForMagpieDiscovery
    case magpie(MagpieProviderReference)
    /// The provider has no magpie rows and no takeover entry, but the standing Claude-family rule
    /// forbids native reads while the switch is on, so it stays unfetched instead of going native.
    case magpieSuspended
    case native

    /// Providers that must never read local credentials, Keychain, OAuth, or browser cookies while
    /// the magpie switch is on — the whole Claude family, whether or not magpie carries them.
    public static let switchOnNativeForbidden: Set<UsageProvider> = [.claude, .claudeplatform]

    /// User-facing message for a suspended provider. Claude Platform has no magpie wire ID at all,
    /// so it gets a plain unavailable state; Claude reports the missing rows like any owned
    /// provider without data.
    public static func suspendedMessage(for provider: UsageProvider) -> String {
        provider == .claudeplatform
            ? "Unavailable while the magpie source is on."
            : "magpie returned no Claude usage rows; native reads stay suspended."
    }

    public static func resolve(
        provider: UsageProvider,
        enabled: Bool,
        ownedWireIDs: Set<String>,
        discoverySucceeded: Bool) -> ProviderSourceRoute
    {
        guard enabled else { return .native }
        let wireIDs = MagpieProviderMapping.wireIDs(for: provider)
        if let owned = wireIDs.first(where: { ownedWireIDs.contains($0) }) {
            return .magpie(MagpieProviderMapping.reference(for: owned))
        }
        if self.switchOnNativeForbidden.contains(provider) {
            return discoverySucceeded ? .magpieSuspended : .waitingForMagpieDiscovery
        }
        guard !wireIDs.isEmpty else { return .native }
        return discoverySucceeded ? .native : .waitingForMagpieDiscovery
    }

    public var isNative: Bool {
        if case .native = self { return true }
        return false
    }
}

#if DEBUG
/// Substitutes sensitive native IO before any real access in boundary tests.
public enum NativeProviderIOTestBoundary {
    public enum Kind: String, Sendable, CaseIterable {
        case context
        case file
        case credential
        case keychain
        case cookie
        case process
    }

    @TaskLocal public static var intercept: (@Sendable (Kind) throws -> Void)?
}
#endif
