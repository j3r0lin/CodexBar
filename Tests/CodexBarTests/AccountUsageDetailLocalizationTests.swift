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
    func `reset lines are localized`() {
        let reset = Date(timeIntervalSince1970: 1_000_000)
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            #expect(AccountUsageDetailView.resetText(reset, now: reset).hasPrefix("Resets "))
        }
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            #expect(AccountUsageDetailView.resetText(reset, now: reset).hasPrefix("重置于 "))
        }
    }

    @Test
    func `clock times name today, tomorrow, the rest of this week, then the date`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
            try #require(calendar.date(from: DateComponents(
                year: 2026,
                month: 10,
                day: day,
                hour: hour,
                minute: minute)))
        }
        // 2026-10-20 is a Tuesday; its week runs to Sunday the 25th.
        let now = try at(20, 9)
        let cases = try [
            (at(20, 14, 30), "14:30"),
            (at(21, 9, 5), "Wed 09:05"),
            (at(22, 14, 30), "Thu 14:30"),
            (at(25, 8), "Sun 08:00"),
            (at(26, 8), "Oct 26 08:00"),
            (at(19, 23), "Oct 19 23:00"),
        ]
        CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            for (date, expected) in cases {
                #expect(AccountUsageDetailView.clockText(date, now: now, calendar: calendar) == expected)
            }
        }
    }

    @Test
    func `pace lines are translated in every catalog`() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/CodexBar/Resources")
        let keys = ["Runs out %@ at this pace", "Lasts past the reset at this pace"]
        for language in AppLanguage.allCases where language != .system {
            let url = resources.appendingPathComponent("\(language.rawValue).lproj/Localizable.strings")
            let catalog = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for key in keys {
                #expect(catalog[key]?.isEmpty == false, "\(language.rawValue): \(key)")
            }
        }
    }

    @Test
    func `blocks list only windows with a reading`() {
        let weekly = self.window(minutes: 7 * 1440, used: 92)
        let lone = AccountUsageDetailView.blocks(of: UsageSnapshot(primary: weekly, secondary: nil, updatedAt: Date()))
        #expect(lone.map(\.used) == [92])
        #expect(AccountUsageDetailView.blocks(of: nil).isEmpty)
    }

    @Test
    func `a magpie detail block follows its window kind for warning thresholds`() throws {
        let account = try #require(MagpieAccountProjection.snapshots(from: [MagpieQuotaRow(
            provider: "claude",
            email: "fixture@example.test",
            organization: "",
            alias: nil,
            isLast: true,
            readAt: nil,
            windows: [
                MagpieQuotaWindow(name: "5 hours", usedPercent: 10, resetsAt: nil),
                MagpieQuotaWindow(name: "7 days", usedPercent: 20, resetsAt: nil),
                MagpieQuotaWindow(name: "Month", usedPercent: 30, resetsAt: nil),
            ])]).first)
        let row = OverviewUsageRow.magpie(
            account: account,
            providerName: "Claude",
            accountName: "Fixture",
            hiddenItemIDs: [])
        let windows = try #require(row.namedWindows)
        let blocks = AccountUsageDetailView.blocks(of: windows)
        #expect(blocks.map(\.warningWindow) == [.session, .weekly, .weekly])
    }

    @Test
    func `a native detail block follows the session or weekly thresholds by window length`() {
        let session = self.window(minutes: 300, used: 20)
        let weekly = self.window(minutes: 7 * 1440, used: 30)
        let untyped = RateWindow(usedPercent: 40, windowMinutes: nil, resetsAt: nil, resetDescription: nil)
        let blocks = AccountUsageDetailView.blocks(
            of: UsageSnapshot(primary: session, secondary: weekly, updatedAt: Date()))
        #expect(blocks.map(\.warningWindow) == [.session, .weekly])
        #expect(AccountUsageDetailView.blocks(
            of: UsageSnapshot(primary: untyped, secondary: nil, updatedAt: Date())).map(\.warningWindow) == [.weekly])
    }

    @Test
    func `a native detail without a model leaves out the lanes the user hid`() {
        let snapshot = UsageSnapshot(
            primary: self.window(minutes: 300, used: 20),
            secondary: self.window(minutes: 7 * 1440, used: 30),
            updatedAt: Date())
        let blocks = AccountUsageDetailView.blocks(of: snapshot, hiddenItemIDs: [.metric("primary")])
        #expect(blocks.map(\.used) == [30])
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
            secondary: self.window(minutes: 7 * 1440, used: 95, resetsAt: reset),
            updatedAt: now)
        let view = HStack(alignment: .top, spacing: 24) {
            AccountUsageDetailView(provider: .grok, providerName: "Grok", snapshot: grok, width: 340, now: now)
            AccountUsageDetailView(
                provider: .claude,
                providerName: "Claude",
                accountName: "claude-1",
                snapshot: claude,
                width: 340,
                now: now)
        }
        .padding(24)
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                AccountUsageDetailView(
                    provider: .claude,
                    providerName: "Claude",
                    accountName: "a-very-long-account-name-for-truncation@example.invalid",
                    snapshot: claude,
                    width: 340,
                    now: now)
                ForEach([0.0, 1, 2, 5, 50, 100], id: \.self) { used in
                    HStack {
                        Text("\(Int(used))%").frame(width: 40, alignment: .trailing)
                        UsageBar(
                            used: used,
                            color: OverviewPalette.color(usedPercent: used),
                            trackColor: OverviewCompactAccountRow.trackColor,
                            height: 5)
                            .frame(width: 41)
                        UsageBar(
                            used: used,
                            color: OverviewPalette.color(usedPercent: used),
                            trackColor: Color.white.opacity(0.16),
                            height: 6)
                            .frame(width: 300)
                    }
                }
            }
            .padding(24)
            .offset(y: 420)
        }
        .padding(.bottom, 420)
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
