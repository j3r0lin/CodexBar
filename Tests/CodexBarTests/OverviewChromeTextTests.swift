import Foundation
import Testing
@testable import CodexBar

@MainActor
struct OverviewChromeTextTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 2026-09-21 14:13:20 UTC.
    private static let updatedAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func subtitle(
        _ date: Date,
        autoRefresh: Bool,
        now: Date? = nil,
        clock: String = "en_GB") -> String
    {
        OverviewChromeText.updatedSubtitle(
            at: date,
            autoRefreshOn: autoRefresh,
            now: now ?? date,
            clockLocale: Locale(identifier: clock),
            calendar: Self.calendar)
    }

    @Test
    func `subtitle names the update time and auto-refresh`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let text = self.subtitle(Self.updatedAt, autoRefresh: true)
            #expect(text == "Updated 14:13 · Auto-refresh")
            #expect(self.subtitle(Self.updatedAt, autoRefresh: false) == "Updated 14:13")
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            #expect(self.subtitle(Self.updatedAt, autoRefresh: true) == "更新于 14:13 · 自动刷新")
            #expect(self.subtitle(Self.updatedAt, autoRefresh: false) == "更新于 14:13")
        }
    }

    @Test
    func `subtitle follows the 12-hour clock setting`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let text = self.subtitle(Self.updatedAt, autoRefresh: true, clock: "en_US")
            #expect(text.contains("2:13"))
            #expect(text.contains("PM"))
            #expect(text.hasSuffix(" · Auto-refresh"))
        }
    }

    @Test
    func `the clock keeps the system 12-hour setting under another app language`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            let text = self.subtitle(Self.updatedAt, autoRefresh: true, clock: "en_US")
            #expect(text.hasPrefix("更新于 "))
            #expect(text.hasSuffix(" · 自动刷新"))
            #expect(text.contains("2:13"))
            #expect(!text.contains("PM"))
        }
    }

    @Test
    func `an update from an earlier day carries its date`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let twoDaysLater = Self.updatedAt.addingTimeInterval(86400 * 2)
            let text = self.subtitle(Self.updatedAt, autoRefresh: false, now: twoDaysLater)
            #expect(text == "Updated 9/21 14:13")
        }
    }

    @Test
    func `footer names the refresh interval the user set`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(OverviewChromeText.autoRefreshStatus(.oneMinute) == "Auto-refresh on · every 1 min")
            #expect(OverviewChromeText.autoRefreshStatus(.fiveMinutes) == "Auto-refresh on · every 5 min")
            #expect(OverviewChromeText.autoRefreshStatus(.fifteenMinutes) == "Auto-refresh on · every 15 min")
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            #expect(OverviewChromeText.autoRefreshStatus(.fiveMinutes) == "自动刷新已开启 · 每 5 分钟")
            #expect(OverviewChromeText.autoRefreshStatus(.thirtyMinutes) == "自动刷新已开启 · 每 30 分钟")
        }
    }

    @Test
    func `footer keeps its plain wording without a fixed interval`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(OverviewChromeText.autoRefreshStatus(.manual) == "Auto-refresh off")
            #expect(OverviewChromeText.autoRefreshStatus(.adaptive) == "Auto-refresh on")
            #expect(OverviewChromeText.autoRefreshStatus(.adaptiveAgentAware) == "Auto-refresh on")
        }
    }
}
