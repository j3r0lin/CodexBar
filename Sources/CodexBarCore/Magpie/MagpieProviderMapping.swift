import Foundation

/// Which provider a magpie wire ID stands for, and how to present it.
///
/// Known wire IDs map onto their native provider so menus and widgets can reuse the native
/// presentation; a mapped provider is magpie-owned while the switch is on and never touches
/// local credentials. Unknown wire IDs keep their raw ID as the display name, get a
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
    /// Provider-specific by design: these verified gateway wire IDs name the matching native providers.
    public static let nativeProviders: [String: UsageProvider] = [
        "claude": .claude,
        "codex": .codex,
        // magpie renamed the Grok wire ID from "grok-plugin" to "grok"; both own the provider,
        // so a takeover persisted under either spelling keeps Grok off local credentials.
        "grok": .grok,
        "grok-plugin": .grok,
        // magpie renamed the Kimi wire ID from "kimi-code" to "kimi", same handling as Grok.
        "kimi": .kimi,
        "kimi-code": .kimi,
        "opencode-go": .opencodego,
    ]

    /// Every wire ID that maps to the provider, sorted so the choice never depends on
    /// Dictionary iteration order. A provider with more than one wire ID is owned when any
    /// of them is in the takeover set.
    public static func wireIDs(for provider: UsageProvider) -> [String] {
        self.nativeProviders.filter { $0.value == provider }.map(\.key).sorted()
    }

    public static func wireID(for provider: UsageProvider) -> String? {
        self.wireIDs(for: provider).first
    }

    public static func reference(for wireID: String) -> MagpieProviderReference {
        if let native = self.nativeProviders[wireID] {
            return MagpieProviderReference(
                wireID: wireID,
                nativeProvider: native,
                instanceID: native.instanceID,
                displayName: ProviderDescriptorRegistry.metadata[native]?.displayName ?? wireID)
        }
        return MagpieProviderReference(
            wireID: wireID,
            nativeProvider: nil,
            instanceID: self.instanceID(forUnknownWireID: wireID),
            displayName: wireID)
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
        var suffix = 1
        while true {
            let fallback = ProviderInstanceID(rawValue: "magpie-\(sanitized)-\(suffix)")!
            if UserProviderPluginRegistry.plugin(for: fallback) == nil { return fallback }
            suffix += 1
        }
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
