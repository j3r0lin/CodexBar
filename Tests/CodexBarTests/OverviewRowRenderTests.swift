import AppKit
import CodexBarCore
import Foundation
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct OverviewRowRenderTests {
    /// Writes the Overview list (three Claude accounts, Kimi Code, Grok with only a weekly window) when
    /// CODEXBAR_OVERVIEW_ROW_RENDER_DIR is set, for checking the layout by eye.
    @Test
    func `render overview rows`() throws {
        guard let dir = ProcessInfo.processInfo.environment["CODEXBAR_OVERVIEW_ROW_RENDER_DIR"] else { return }
        let now = Date()
        func window(_ minutes: Int, _ used: Double, _ resetMinutes: Double) -> RateWindow {
            RateWindow(
                usedPercent: used,
                windowMinutes: minutes,
                resetsAt: now.addingTimeInterval(resetMinutes * 60),
                resetDescription: nil)
        }
        let width: CGFloat = 340
        struct Account {
            let name: String
            let session: RateWindow
            let weekly: RateWindow
        }
        let accounts = [
            Account(name: "claude-1", session: window(300, 46, 18), weekly: window(10080, 95, 598)),
            Account(name: "claude", session: window(300, 0, 70), weekly: window(10080, 84, 2340)),
            Account(name: "claude-2", session: window(300, 2, 70), weekly: window(10080, 100, 178)),
        ]
        let view = VStack(alignment: .leading, spacing: 0) {
            OverviewCompactAccountRow(
                name: "Codex",
                shortWindow: window(300, 96, 140),
                longWindow: window(10080, 15, 9900),
                width: width,
                namesProvider: true,
                now: now)
            OverviewAccountGroupHeading(title: "Claude · 3 accounts", width: width)
            ForEach(accounts.indices, id: \.self) { index in
                let account = accounts[index]
                OverviewCompactAccountRow(
                    name: account.name,
                    shortWindow: account.session,
                    longWindow: account.weekly,
                    width: width,
                    indent: 10,
                    block: index == accounts.count - 1 ? .bottom : .middle,
                    now: now)
            }
            OverviewCompactAccountRow(
                name: "Kimi Code",
                shortWindow: window(300, 8, 5880),
                longWindow: window(10080, 10, 52),
                width: width,
                namesProvider: true,
                now: now)
            OverviewCompactAccountRow(
                name: "Grok",
                shortWindow: nil,
                longWindow: window(10080, 90, 6960),
                width: width,
                namesProvider: true,
                now: now)
        }
        .padding(.vertical, 6)
        .background(Color(red: 0.14, green: 0.14, blue: 0.16))
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let bitmap = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("overview-rows.png"))
    }
}
