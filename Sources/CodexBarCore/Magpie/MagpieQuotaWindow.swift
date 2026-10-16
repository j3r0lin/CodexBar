import Foundation

/// One quota window as reported by magpie, keeping the wire name and optional duration.
///
/// Window semantics decide which UI slot a window fills: when the wire reports a duration the
/// duration wins, otherwise the window name decides ("5 hours", "7 days", "Month"). A window
/// named "Month" carries no hardcoded 30-day duration; unknown names stay `.other` and keep
/// their original name for display.
public struct MagpieQuotaWindow: Sendable, Equatable {
    public enum Semantics: Sendable, Equatable {
        /// Short session-style window (magpie's "5 hours").
        case session
        /// Provider-wide weekly window ("7 days").
        case weekly
        /// Model-scoped weekly window ("7 days · Fable"); the model name is preserved.
        case scopedWeekly(model: String)
        /// Calendar-month-style window ("Month"); duration is not assumed.
        case monthly
        /// Anything else, displayed under its original name.
        case other
    }

    public static let sessionWindowName = "5 hours"
    public static let weeklyWindowName = "7 days"
    public static let scopedWeeklyPrefix = "7 days · "
    public static let monthWindowName = "Month"
    static let sessionWindowMinutes = 5 * 60
    static let weeklyWindowMinutes = 7 * 24 * 60

    public let name: String
    public let usedPercent: Double
    public let resetsAt: Date?
    /// Window length when known; nil when the wire does not report one and the name does not
    /// imply a fixed length (monthly and unknown windows stay nil).
    public let duration: TimeInterval?
    public let semantics: Semantics

    public init(name: String, usedPercent: Double, resetsAt: Date?, duration: TimeInterval? = nil) {
        self.name = name
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.duration = duration ?? Self.impliedDuration(forName: name)
        self.semantics = Self.semantics(forName: name, duration: duration)
    }

    private static func impliedDuration(forName name: String) -> TimeInterval? {
        switch name {
        case self.sessionWindowName:
            TimeInterval(self.sessionWindowMinutes * 60)
        case self.weeklyWindowName:
            TimeInterval(self.weeklyWindowMinutes * 60)
        default:
            nil
        }
    }

    private static func semantics(forName name: String, duration: TimeInterval?) -> Semantics {
        if let duration {
            return self.semantics(forDuration: duration, name: name)
        }
        if name == self.sessionWindowName { return .session }
        if name == self.weeklyWindowName { return .weekly }
        if name.hasPrefix(self.scopedWeeklyPrefix) {
            return .scopedWeekly(model: String(name.dropFirst(self.scopedWeeklyPrefix.count)))
        }
        if name == self.monthWindowName { return .monthly }
        return .other
    }

    private static func semantics(forDuration duration: TimeInterval, name: String) -> Semantics {
        if name.hasPrefix(self.scopedWeeklyPrefix) {
            return .scopedWeekly(model: String(name.dropFirst(self.scopedWeeklyPrefix.count)))
        }
        let hours = duration / 3600
        if hours <= 24 { return .session }
        let days = duration / 86_400
        if days <= 8 { return .weekly }
        return .monthly
    }
}
