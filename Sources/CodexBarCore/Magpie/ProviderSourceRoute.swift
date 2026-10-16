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
    case native

    public var isNative: Bool {
        if case .native = self { return true }
        return false
    }
}

#if DEBUG
/// Substitutes sensitive native IO before any real access in boundary tests.
public enum NativeProviderIOTestBoundary {
    public enum Kind: String, Sendable, CaseIterable {
        case file
        case credential
        case keychain
        case cookie
        case process
    }

    @TaskLocal public static var intercept: (@Sendable (Kind) throws -> Void)?
}
#endif
