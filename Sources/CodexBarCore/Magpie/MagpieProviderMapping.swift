import Foundation

/// Which provider a magpie wire ID stands for, and how to present it.
///
/// Known wire IDs map onto their native provider so menus and widgets can reuse the native
/// presentation. `grok-plugin` deliberately maps to no native provider: until equivalence with
/// the native Grok provider is confirmed it renders as a generic row named "Grok" and never
/// touches `.grok` credentials. Unknown wire IDs keep their raw ID as the display name, get a
/// `magpie-`-prefixed instance ID, and never register a fake native descriptor.
public struct MagpieProviderReference: Hashable, Sendable {
    public let wireID: String
    public let nativeProvider: UsageProvider?
    public let instanceID: ProviderInstanceID
    public let displayName: String

    public init(wireID: String, nativeProvider: UsageProvider?, instanceID: ProviderInstanceID, displayName: String) {
        self.wireID = wireID
        self.nativeProvider = nativeProvider
        self.instanceID = instanceID
        self.displayName = displayName
    }
}

public enum MagpieProviderMapping {
    /// Wire IDs whose rows CodexBar presents through the native provider's identity.
    public static let nativeProviders: [String: UsageProvider] = [
        "claude": .claude,
        "codex": .codex,
        "kimi-code": .kimi,
        "opencode-go": .opencodego,
    ]

    /// Generic rows with a fixed display name but no native provider.
    private static let genericDisplayNames: [String: String] = [
        "grok-plugin": "Grok",
    ]

    public static func wireID(for provider: UsageProvider) -> String? {
        self.nativeProviders.first(where: { $0.value == provider })?.key
    }

    public static func reference(for wireID: String) -> MagpieProviderReference {
        if let native = self.nativeProviders[wireID] {
            return MagpieProviderReference(
                wireID: wireID,
                nativeProvider: native,
                instanceID: native.instanceID,
                displayName: ProviderDescriptorRegistry.metadata[native]?.displayName ?? wireID)
        }
        let displayName = self.genericDisplayNames[wireID] ?? wireID
        return MagpieProviderReference(
            wireID: wireID,
            nativeProvider: nil,
            instanceID: self.instanceID(forUnknownWireID: wireID),
            displayName: displayName)
    }

    /// Unknown providers get a `magpie-`-prefixed instance ID. If a user plugin already owns the
    /// candidate ID the reference falls back to a suffixed variant so rows never alias a plugin's
    /// state; no descriptor is registered either way.
    static func instanceID(forUnknownWireID wireID: String) -> ProviderInstanceID {
        let sanitized = Self.sanitizedInstanceIDComponent(wireID)
        if let candidate = ProviderInstanceID(rawValue: "magpie-\(sanitized)"),
           UserProviderPluginRegistry.plugin(for: candidate) == nil
        {
            return candidate
        }
        if let fallback = ProviderInstanceID(rawValue: "magpie-\(sanitized)-ext") {
            return fallback
        }
        // Unreachable in practice: sanitization guarantees a valid component.
        return ProviderInstanceID(firstPartyProvider: .codex)
    }

    private static func sanitizedInstanceIDComponent(_ wireID: String) -> String {
        let lowered = wireID.lowercased()
        let mapped = lowered.map { char -> Character in
            if char.isASCII, char.isLetter || char.isNumber || char == "-" { return char }
            return "-"
        }
        let trimmed = String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let component = trimmed.isEmpty ? "provider" : trimmed
        return String(component.prefix(48))
    }
}
