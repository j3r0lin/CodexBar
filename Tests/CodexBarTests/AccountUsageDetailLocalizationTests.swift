import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct AccountUsageDetailLocalizationTests {
    private func window(minutes: Int) -> RateWindow {
        RateWindow(usedPercent: 10, windowMinutes: minutes, resetsAt: nil, resetDescription: nil)
    }

    @Test
    func `window titles follow the plural rules of the app language`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 1440)) == "1 day")
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 7 * 1440)) == "7 days")
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 300)) == "5 hours")
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 1)) == "1 minute")
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("ru") {
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 300)) == "5 часов")
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 120)) == "2 часа")
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 7 * 1440)) == "7 天")
        }
    }

    @Test
    func `usage line and data age are localized`() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        CodexBarLocalizationOverride.$appLanguage.withValue("de") {
            #expect(AccountUsageDetailView.usageText(used: 40, resetsAt: nil, now: now) == "40%")
            #expect(AccountUsageDetailView.ageText(now, now: now) == L("Updated just now"))
            #expect(L("Updated just now") != "Updated just now")
            let withReset = AccountUsageDetailView.usageText(used: 40, resetsAt: now.addingTimeInterval(3600), now: now)
            let countdown = OverviewCompactAccountRow.countdown(to: now.addingTimeInterval(3600), now: now)
            #expect(withReset == "40% · " + L("Resets in %@", countdown))
        }
    }
}
