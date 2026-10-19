import CodexBarCore

extension StatusItemController {
    nonisolated static func pluginSwitcherMetricPercent(snapshot: UsageSnapshot?, showUsed: Bool) -> Double? {
        let windows = ([snapshot?.primary, snapshot?.secondary, snapshot?.tertiary].compactMap(\.self) +
            (snapshot?.extraRateWindows ?? []).filter(\.usageKnown).map(\.window))
            .filter(\.usedPercent.isFinite)
        let weekly = windows.filter { $0.windowMinutes == 7 * 24 * 60 }
            .max { $0.usedPercent < $1.usedPercent }
        guard let window = weekly ?? windows.first else { return nil }
        let used = min(100, max(0, window.usedPercent))
        return showUsed ? used : 100 - used
    }
}
