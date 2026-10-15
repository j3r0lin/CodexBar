import AppKit
import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct AccountUsageDetailLocalizationTests {
    private func window(minutes: Int?, used: Double = 10, resetsAt: Date? = nil) -> RateWindow {
        RateWindow(usedPercent: used, windowMinutes: minutes, resetsAt: resetsAt, resetDescription: nil)
    }

    @Test
    func `window titles name the session and weekly limits and pluralize the rest`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 300)) == "5-hour limit")
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 7 * 1440)) == "Weekly limit")
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 1440)) == "1 day")
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 120)) == "2 hours")
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 1)) == "1 minute")
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("ru") {
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 120)) == "2 часа")
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 7 * 1440)) == "Недельный лимит")
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            #expect(AccountUsageDetailView.windowTitle(self.window(minutes: 3 * 1440)) == "3 天")
        }
    }

    @Test
    func `used and reset lines are localized`() {
        let reset = Date(timeIntervalSince1970: 1_000_000)
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(AccountUsageDetailView.usedText(92) == "92% Used")
            #expect(AccountUsageDetailView.resetText(reset).hasPrefix("Resets "))
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            #expect(AccountUsageDetailView.usedText(92) == "已用 92%")
            #expect(AccountUsageDetailView.resetText(reset).hasPrefix("重置于 "))
        }
    }

    @Test
    func `blocks list only windows with a reading`() {
        let weekly = self.window(minutes: 7 * 1440, used: 92)
        let lone = AccountUsageDetailView.blocks(of: UsageSnapshot(primary: weekly, secondary: nil, updatedAt: Date()))
        #expect(lone.map(\.used) == [92])
        #expect(AccountUsageDetailView.blocks(of: nil).isEmpty)
    }

    /// Writes the card for a weekly-only provider and a two-window provider when
    /// CODEXBAR_DETAIL_CARD_RENDER_DIR is set, for comparing against the design reference.
    @Test
    func `render detail cards`() throws {
        guard let dir = ProcessInfo.processInfo.environment["CODEXBAR_DETAIL_CARD_RENDER_DIR"] else { return }
        let now = Date()
        let reset = now.addingTimeInterval(4 * 86400 + 20 * 3600)
        let grok = UsageSnapshot(
            primary: self.window(minutes: 7 * 1440, used: 92, resetsAt: reset),
            secondary: nil,
            updatedAt: now)
        let claude = UsageSnapshot(
            primary: self.window(minutes: 300, used: 38, resetsAt: now.addingTimeInterval(2 * 3600)),
            secondary: self.window(minutes: 7 * 1440, used: 61, resetsAt: reset),
            updatedAt: now)
        let view = HStack(alignment: .top, spacing: 24) {
            AccountUsageDetailView(provider: .grok, providerName: "Grok", snapshot: grok, width: 340, now: now)
            AccountUsageDetailView(
                provider: .claude,
                providerName: "Claude",
                accountName: "Account 1",
                snapshot: claude,
                width: 340,
                now: now)
        }
        .padding(24)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let bitmap = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("detail-cards.png"))
        }
    }
}
