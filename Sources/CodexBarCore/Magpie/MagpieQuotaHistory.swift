import Foundation

/// One reading magpie kept of a window: what was `left` (percent) at `at`, with the cycle the vendor
/// reported then when it reported one.
public struct MagpieQuotaHistoryPoint: Sendable, Equatable {
    public let at: Date
    public let left: Double
    public let start: Date?
    public let resetsAt: Date?

    public init(at: Date, left: Double, start: Date? = nil, resetsAt: Date? = nil) {
        self.at = at
        self.left = left
        self.start = start
        self.resetsAt = resetsAt
    }
}

/// Readings of every account's windows from magpie's quota history, keyed the way account rows are:
/// the opaque fingerprint of (canonical wire ID, email, organization), then the window's wire name
/// (pooled windows are named `pool · name`).
public struct MagpieQuotaHistory: Sendable {
    private let lines: [String: [String: [MagpieQuotaHistoryPoint]]]

    /// The readings of one account's window, oldest first; empty when magpie kept none.
    public func points(for account: ProviderAccountIdentity, window name: String) -> [MagpieQuotaHistoryPoint] {
        guard account.source == MagpieAccountProjection.sourceName else { return [] }
        return self.lines[account.opaqueID]?[name] ?? []
    }

    /// Builds the history from parsed accounts. Wire IDs that name one native provider share its
    /// canonical ID, and a user-less account matches the provider-level row, so a history account
    /// lands on the same fingerprint as its quota row.
    public init(accounts: [MagpieQuotaHistoryAccount]) {
        var lines: [String: [String: [MagpieQuotaHistoryPoint]]] = [:]
        for account in accounts {
            let reference = MagpieProviderMapping.reference(for: account.provider)
            let wireID = reference.nativeProvider.flatMap(MagpieProviderMapping.wireID(for:)) ?? account.provider
            let user = MagpieQuotasReader.splitUser(account.user)
            let key = MagpieAccountProjection.identityFingerprint(
                wireID: wireID,
                email: user.email.isEmpty ? "\u{0}provider" : user.email,
                organization: user.email.isEmpty ? "" : user.organization)
            for line in account.lines {
                lines[key, default: [:]][line.name, default: []].append(contentsOf: line.points)
            }
        }
        self.lines = lines.mapValues { $0.mapValues { $0.sorted { $0.at < $1.at } } }
    }
}

/// One account of the history response: its wire provider, its raw `user`, and its windows' readings.
public struct MagpieQuotaHistoryAccount: Sendable {
    public struct Line: Sendable {
        public let name: String
        public let points: [MagpieQuotaHistoryPoint]

        public init(name: String, points: [MagpieQuotaHistoryPoint]) {
            self.name = name
            self.points = points
        }
    }

    public let provider: String
    public let user: String
    public let lines: [Line]

    public init(provider: String, user: String, lines: [Line]) {
        self.provider = provider
        self.user = user
        self.lines = lines
    }
}

/// A window's current cycle read from its history, and where its own readings are taking it.
/// Ported from magpie's tray panel (app.js `quotaCycleBreak`, `quotaCycle`, `quotaEta`) so the
/// two apps agree on when a window started again and when it runs out.
public enum MagpieQuotaTrend {
    public struct Cycle: Sendable, Equatable {
        public let start: Date
        /// Nil when the window reports no reset or its reset has passed.
        public let reset: Date?
    }

    public enum Eta: Sendable, Equatable {
        /// The fitted line reaches zero at this time, before the reset (or the window has none).
        case runsOut(Date)
        case lastsPastReset
    }

    /// The span a pace is fitted over: what the window is spending now, not its whole history.
    static let etaSpan: TimeInterval = 7 * 86400
    static let breakSlack: TimeInterval = 5 * 60

    /// Whether `b`, read after `a`, belongs to a new cycle: the reset moved by more than the
    /// slack, passed, or `left` rose more than 5 points without the reset moving.
    public static func cycleBreak(_ a: MagpieQuotaHistoryPoint, _ b: MagpieQuotaHistoryPoint) -> Bool {
        guard let aReset = a.resetsAt, let bReset = b.resetsAt else {
            if a.resetsAt == nil, b.resetsAt == nil { return b.left > a.left + 5 }
            return true
        }
        if aReset <= b.at { return true }
        let moved = bReset.timeIntervalSince(aReset)
        let gap = b.at.timeIntervalSince(a.at)
        let rolling = moved > 0 && abs(moved - gap) <= self.breakSlack
        if !rolling, abs(moved) <= self.breakSlack, b.left > a.left + 5 { return true }
        return moved > gap + self.breakSlack || moved < -self.breakSlack
    }

    /// The current cycle: the window's own reset when it has one, else the last reading's, and the
    /// start the vendor reported, else the first reading since the last cycle break.
    public static func currentCycle(
        points: [MagpieQuotaHistoryPoint],
        resetsAt: Date?,
        now: Date) -> Cycle?
    {
        guard let last = points.last else { return nil }
        var reset = resetsAt ?? last.resetsAt
        var start: Date? = if let lastStart = last.start, let lastReset = last.resetsAt, let reset {
            lastStart.addingTimeInterval(reset.timeIntervalSince(lastReset))
        } else {
            last.start
        }
        if start == nil {
            var index = points.count - 1
            while index > 0, !self.cycleBreak(points[index - 1], points[index]) {
                index -= 1
            }
            start = points[index].at
        }
        var cycleStart = start ?? last.at
        if reset == last.resetsAt {
            cycleStart = max(cycleStart, self.lastRecordedCycleStart(points))
        }
        if let current = reset, current <= now { reset = nil }
        return Cycle(start: min(cycleStart, now), reset: reset)
    }

    /// The readings of the current cycle up to now, from the last cycle break on.
    public static func cyclePoints(
        _ points: [MagpieQuotaHistoryPoint],
        cycle: Cycle,
        now: Date) -> [MagpieQuotaHistoryPoint]
    {
        var current: [MagpieQuotaHistoryPoint] = []
        for point in points where point.at >= cycle.start && point.at <= now {
            if let previous = current.last, self.cycleBreak(previous, point) { current = [] }
            current.append(point)
        }
        return current
    }

    /// Least-squares line through the readings since the window last refilled, within the last
    /// week, carried to where it meets zero. Nil with fewer than three readings, less than an hour
    /// of them, nothing left, or a line that already passed zero.
    public static func eta(points: [MagpieQuotaHistoryPoint], cycle: Cycle, now: Date) -> Eta? {
        if let reset = cycle.reset, reset <= now { return nil }
        let inCycle = points.filter { $0.at >= cycle.start && $0.at <= now }
        guard !inCycle.isEmpty else { return nil }
        var first = inCycle.count - 1
        while first > 0, inCycle[first - 1].left >= inCycle[first].left,
              now.timeIntervalSince(inCycle[first - 1].at) <= self.etaSpan
        {
            first -= 1
        }
        let fitted = inCycle[first...]
        guard fitted.count >= 3, let head = fitted.first, let tail = fitted.last, tail.left > 0,
              tail.at.timeIntervalSince(head.at) >= 3600
        else { return nil }
        let n = Double(fitted.count)
        var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
        for point in fitted {
            let x = point.at.timeIntervalSince(head.at) / 86400
            sx += x
            sy += point.left
            sxx += x * x
            sxy += x * point.left
        }
        let den = n * sxx - sx * sx
        guard den > 0 else { return nil }
        let slope = (n * sxy - sx * sy) / den
        guard slope < 0 else { return cycle.reset == nil ? nil : .lastsPastReset }
        let out = head.at.addingTimeInterval(-(sy - slope * sx) / n / slope * 86400)
        guard out > now else { return nil }
        if let reset = cycle.reset, out >= reset { return .lastsPastReset }
        return .runsOut(out)
    }

    /// The start of the last cycle the readings themselves record. An early reset starts the new
    /// cycle at its first reading unless the vendor's start falls between the two readings.
    private static func lastRecordedCycleStart(_ points: [MagpieQuotaHistoryPoint]) -> Date {
        var start = points.first?.at ?? .distantPast
        var previous: MagpieQuotaHistoryPoint?
        for point in points {
            defer { previous = point }
            guard let prev = previous else {
                start = point.start ?? point.at
                continue
            }
            guard self.cycleBreak(prev, point) else { continue }
            var candidate = point.start ?? point.at
            let resetStillAhead = prev.resetsAt.map { $0 > point.at } ?? true
            if resetStillAhead, !(candidate > prev.at && candidate <= point.at) { candidate = point.at }
            if let prevReset = prev.resetsAt, prevReset <= point.at { candidate = max(candidate, prevReset) }
            start = candidate
        }
        return start
    }
}
