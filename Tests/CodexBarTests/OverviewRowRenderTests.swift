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
        let width: CGFloat = 400
        struct Account {
            let name: String
            let session: RateWindow
            let weekly: RateWindow
        }
        let accounts = [
            Account(name: "claude", session: window(300, 46, 138), weekly: window(10080, 10, 8912)),
            Account(name: "claude-1", session: window(300, 12, 188), weekly: window(10080, 22, 7418)),
            Account(name: "claude-2", session: window(300, 0, 70), weekly: window(10080, 98, 248)),
        ]
        let view = VStack(alignment: .leading, spacing: 0) {
            ForEach(accounts.indices, id: \.self) { index in
                let account = accounts[index]
                OverviewCompactAccountRow(
                    name: account.name,
                    shortWindow: account.session,
                    longWindow: account.weekly,
                    width: width,
                    namesProvider: true,
                    now: now)
            }
            OverviewCompactAccountRow(
                name: "Codex",
                shortWindow: window(300, 96, 140),
                longWindow: window(10080, 15, 9900),
                width: width,
                namesProvider: true,
                now: now)
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

    /// Writes the paced 7d bar and the long-name layouts when CODEXBAR_ROW_RENDER_DIR is set, for
    /// comparing the bar thickness and the name wrapping by eye.
    @Test
    func `render pace bar and long names`() throws {
        guard let dir = ProcessInfo.processInfo.environment["CODEXBAR_ROW_RENDER_DIR"] else { return }
        let now = Date()
        let width: CGFloat = 400
        func line(
            _ label: String,
            _ used: Double,
            pace: Double? = nil,
            tone: OverviewCompactAccountRow.PaceTone = .neutral)
            -> OverviewCompactAccountRow.Line
        {
            .init(
                label: label,
                used: used,
                resetsAt: now.addingTimeInterval(3 * 86400),
                pacePercent: pace,
                paceTone: tone)
        }
        func row(_ name: String, _ lines: [OverviewCompactAccountRow.Line], provider: Bool = true)
            -> OverviewCompactAccountRow
        {
            OverviewCompactAccountRow(
                name: name,
                shortWindow: nil,
                longWindow: nil,
                width: width,
                namesProvider: provider,
                namedLines: lines,
                now: now)
        }
        func write(_ name: String, _ content: some View) throws {
            let view = content
                .padding(.vertical, 6)
                .background(Color(red: 0.14, green: 0.14, blue: 0.16))
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let bitmap = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        try write("pace-bars", VStack(alignment: .leading, spacing: 8) {
            row("Claude", [line("5h", 40), line("7d", 40, pace: 50)])
            row("Codex", [line("5h", 40), line("7d", 60, pace: 50, tone: .runsOut)])
        })
        try write("long-names", VStack(alignment: .leading, spacing: 8) {
            row("Some Very Long Provider Name", [line("5h", 40), line("7d", 40, pace: 50)])
            row("OpenCode Go", [line("5h", 40), line("7d", 40, pace: 50)])
            row("Some Very Long Account Name", [line("5h", 40)], provider: false)
        })
    }

    /// Writes the Overview footer before the redesign and both separator treatments after it, when
    /// CODEXBAR_FOOTER_RENDER_DIR is set.
    @Test
    func `render overview footer`() throws {
        guard let dir = ProcessInfo.processInfo.environment["CODEXBAR_FOOTER_RENDER_DIR"] else { return }
        let width: CGFloat = 400
        let now = Date()
        func window(_ minutes: Int, _ used: Double) -> RateWindow {
            RateWindow(
                usedPercent: used,
                windowMinutes: minutes,
                resetsAt: now.addingTimeInterval(3600),
                resetDescription: nil)
        }
        let context = VStack(alignment: .leading, spacing: 0) {
            OverviewCardHeaderView(title: "CodexBar", updatedText: "Updated 2m ago", width: width)
            OverviewCompactAccountRow(
                name: "claude",
                shortWindow: window(300, 46),
                longWindow: window(10080, 10),
                width: width,
                namesProvider: true,
                block: .single,
                now: now)
            OverviewCompactAccountRow(
                name: "claude-1",
                shortWindow: window(300, 12),
                longWindow: window(10080, 98),
                width: width,
                namesProvider: true,
                block: .single,
                now: now)
        }
        func write(_ name: String, _ content: some View) throws {
            let view = content
                .background(Color(red: 0.14, green: 0.14, blue: 0.16))
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let bitmap = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
        let fullWidthSeparator = Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(height: 1)
        // The old footer: a status line naming the last sync, then a centred borderless icon bar.
        let legacyFooter = VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(red: 0.24, green: 0.84, blue: 0.44))
                    .frame(width: 7, height: 7)
                Text("Auto-refresh on")
                    .font(.system(size: 11))
                    .foregroundStyle(OverviewPalette.caption)
                Spacer(minLength: 8)
                Text("Last sync: 14:32")
                    .font(.system(size: 11))
                    .foregroundStyle(OverviewPalette.caption)
            }
            .padding(.horizontal, OverviewCompactAccountRow.horizontalPadding)
            .padding(.vertical, 6)
            HStack(spacing: 22) {
                Image(systemName: "info.circle")
                Image(systemName: "power")
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color(white: 0.78))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
        }
        .frame(width: width, alignment: .leading)
        try write("before", VStack(alignment: .leading, spacing: 0) {
            context
            fullWidthSeparator
            legacyFooter
        })
        // The rejected treatment: a hairline at the card inset above the footer row.
        try write("after-inset-line", VStack(alignment: .leading, spacing: 0) {
            context
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.horizontal, OverviewCompactAccountRow.blockInset)
                .padding(.bottom, 2)
            OverviewFooterView(
                autoRefreshOn: true,
                aboutHelp: "About CodexBar (v1.2.3)",
                quitHelp: "Quit",
                width: width)
        })
        try write("after-no-separator", VStack(alignment: .leading, spacing: 0) {
            context
            OverviewFooterView(
                autoRefreshOn: true,
                aboutHelp: "About CodexBar (v1.2.3)",
                quitHelp: "Quit",
                width: width)
        })
    }

    private static func writeSidePageRender(_ name: String, _ content: some View) throws {
        guard let dir = ProcessInfo.processInfo.environment["CODEXBAR_SIDE_PAGE_RENDER_DIR"] else { return }
        let view = content
            .background(Color(red: 0.14, green: 0.14, blue: 0.16))
            .environment(\.colorScheme, .dark)
        try CodexBarLocalizationOverride.$appLanguage.withValue("en") {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let bitmap = try NSBitmapImageRep(cgImage: #require(renderer.cgImage))
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    /// Writes the Overview list when CODEXBAR_SIDE_PAGE_RENDER_DIR is set: synthetic accounts, placeholder
    /// names only.
    @Test
    func `render overview list`() throws {
        guard ProcessInfo.processInfo.environment["CODEXBAR_SIDE_PAGE_RENDER_DIR"] != nil else { return }
        let now = Date()
        let width: CGFloat = 400
        let hour: TimeInterval = 3600, day: TimeInterval = 86400
        func write(_ name: String, _ content: some View) throws {
            try Self.writeSidePageRender(name, content)
        }
        func line(
            _ label: String,
            _ used: Double,
            resetIn: TimeInterval,
            pace: Double? = nil,
            tone: OverviewCompactAccountRow.PaceTone = .neutral) -> OverviewCompactAccountRow.Line
        {
            .init(
                label: label,
                used: used,
                resetsAt: now.addingTimeInterval(resetIn),
                pacePercent: pace,
                paceTone: tone)
        }
        func row(
            _ name: String,
            _ lines: [OverviewCompactAccountRow.Line],
            provider: Bool = true,
            block: OverviewBlockPosition = .single) -> OverviewCompactAccountRow
        {
            OverviewCompactAccountRow(
                name: name,
                shortWindow: nil,
                longWindow: nil,
                width: width,
                namesProvider: provider,
                block: block,
                namedLines: lines,
                now: now)
        }
        /// The highlight MenuRowContainerView paints behind a hovered Overview row, for the selection block.
        func highlighted(_ view: some View, block: OverviewBlockPosition) -> some View {
            let radius: CGFloat = block == .middle ? 0 : 10
            return view.background(alignment: .top) {
                UnevenRoundedRectangle(
                    topLeadingRadius: block.roundsTop ? radius : 0,
                    bottomLeadingRadius: block.roundsBottom ? radius : 0,
                    bottomTrailingRadius: block.roundsBottom ? radius : 0,
                    topTrailingRadius: block.roundsTop ? radius : 0)
                    .fill(Color.white.opacity(0.10))
                    .padding(.horizontal, OverviewCompactAccountRow.blockInset)
                    .padding(.bottom, block.roundsBottom ? OverviewCompactAccountRow.blockGap : 0)
            }
        }

        let account1 = [
            line("5h", 75, resetIn: 1.5 * hour),
            line("7d", 30, resetIn: 4 * day, pace: 43),
            line("Fable", 5, resetIn: 4 * day),
        ]
        let account2 = [
            line("5h", 64, resetIn: 25 * 60),
            line("7d", 62, resetIn: 2.4 * day, pace: 66, tone: .runsOut),
            line("Fable", 0, resetIn: 2.4 * day),
        ]
        let account3 = [
            line("5h", 27, resetIn: 2 * hour + 12 * 60),
            line("7d", 34, resetIn: 3.5 * day, pace: 50, tone: .neutral),
            line("Fable", 0, resetIn: 3.5 * day),
        ]
        let kimi = [
            line("5h", 0, resetIn: 2 * hour),
            line("7d", 0, resetIn: 6 * day),
            line("30d", 83, resetIn: 22 * day + 4 * hour),
        ]
        let list = VStack(alignment: .leading, spacing: 0) {
            row("Codex", [line("5h", 12, resetIn: 3 * hour), line("7d", 41, resetIn: 4 * day, pace: 45)])
            highlighted(row("account-1", account1, provider: true, block: .single), block: .single)
            row("account-2", account2, provider: true, block: .single)
            row("account-3", account3, provider: true, block: .single)
            row("Kimi Code", kimi)
            row("Grok", [line("7d", 1, resetIn: 6 * day + 22 * hour, pace: 2)])
        }
        try write("a-overview-list", list.padding(.vertical, 6))
    }

    @Test
    func `render unlimited quota filtering`() throws {
        guard ProcessInfo.processInfo.environment["CODEXBAR_SIDE_PAGE_RENDER_DIR"] != nil else { return }
        let accounts = try MagpieAccountProjection.snapshots(from: MagpieQuotasReader.rows(from: Data("""
        {"data":[{"provider":"unlimited-provider","windows":[{"name":"Limit","used":0,"unlimited":true}]},
          {"provider":"claude","alias":"all-unlimited","windows":[{"name":"5 hours","used":0,"unlimited":true}]},
          {"provider":"claude","alias":"mixed-account","user":"fixture","windows":[
            {"name":"5 hours","used":0,"unlimited":true},{"name":"7 days","used":42}]}]}
        """.utf8)))
        let visible = accounts.filter { !$0.hasOnlyUnlimitedWindows }
        #expect(visible.count == 1)
        let view = VStack(alignment: .leading, spacing: 0) {
            Text("Overview · \(Set(visible.map(\.provider.wireID)).count) provider")
                .font(.system(size: 12, weight: .semibold))
                .padding(12)
            ForEach(visible) { account in
                let row = OverviewUsageRow.magpie(
                    account: account,
                    providerName: account.provider.displayName,
                    accountName: account.displayLabel)
                OverviewCompactAccountRow(
                    name: "\(account.provider.displayName) · \(account.displayLabel)",
                    shortWindow: nil,
                    longWindow: nil,
                    width: 400,
                    namedLines: row.compactLines(now: Date()),
                    now: Date())
            }
        }
        try Self.writeSidePageRender("unlimited-filtered-overview", view.padding(.vertical, 6))
    }

    /// Writes the side pages and the footer when CODEXBAR_SIDE_PAGE_RENDER_DIR is set: synthetic readings,
    /// placeholder names only.
    @Test
    func `render side pages and footer`() throws {
        guard ProcessInfo.processInfo.environment["CODEXBAR_SIDE_PAGE_RENDER_DIR"] != nil else { return }
        let now = Date()
        let width: CGFloat = 400
        let hour: TimeInterval = 3600, day: TimeInterval = 86400
        func write(_ name: String, _ content: some View) throws {
            try Self.writeSidePageRender(name, content)
        }
        func points(
            start: Date,
            reset: Date,
            every: TimeInterval,
            left: (Double) -> Double) -> [MagpieQuotaHistoryPoint]
        {
            stride(from: start.timeIntervalSince1970, through: now.timeIntervalSince1970, by: every).map {
                let at = Date(timeIntervalSince1970: $0)
                return MagpieQuotaHistoryPoint(
                    at: at,
                    left: left(at.timeIntervalSince(start) / reset.timeIntervalSince(start)),
                    start: start,
                    resetsAt: reset)
            }
        }
        let sessionReset = now.addingTimeInterval(1.5 * hour), weeklyReset = now.addingTimeInterval(4 * day)
        let sessionStart = sessionReset.addingTimeInterval(-5 * hour)
        let weeklyStart = weeklyReset.addingTimeInterval(-7 * day)
        // The session burns slowly, then fast: behind the even burn and out before its reset.
        let session = points(start: sessionStart, reset: sessionReset, every: 15 * 60) { progress in
            progress < 0.3 ? 100 - progress * 33 : 90 - (progress - 0.3) * 175
        }
        // The week stays above the even burn with a busy middle day.
        let weekly = points(start: weeklyStart, reset: weeklyReset, every: 2 * hour) { progress in
            progress < 0.2 ? 100 - progress * 40 : progress < 0.32 ? 92 - (progress - 0.2) * 150 : 74 -
                (progress - 0.32) * 36
        }
        let fable = points(start: weeklyStart, reset: weeklyReset, every: 9 * hour) { progress in 100 - progress * 12 }
        func named(_ name: String, _ used: Double, _ reset: Date, _ history: [MagpieQuotaHistoryPoint] = [])
            -> OverviewUsageRow.NamedWindow
        {
            OverviewUsageRow.NamedWindow(
                window: MagpieQuotaWindow(name: name, usedPercent: used, resetsAt: reset),
                history: history)
        }
        func page(_ windows: [OverviewUsageRow.NamedWindow], error: String? = nil, stale: Bool = false) -> some View {
            AccountUsageDetailView(
                provider: .claude,
                providerName: "Claude",
                accountName: "account-1",
                snapshot: nil,
                namedWindows: windows,
                errorText: error,
                width: width,
                now: now,
                readAt: now.addingTimeInterval(stale ? -2 * hour : -2 * 60),
                isStale: stale)
        }
        let used = [
            ("5 hours", 100 - (session.last?.left ?? 100), sessionReset, session),
            ("7 days", 100 - (weekly.last?.left ?? 100), weeklyReset, weekly),
            ("7 days · Fable", 100 - (fable.last?.left ?? 100), weeklyReset, fable),
        ]
        try write("b-side-page-magpie", page(used.map { named($0.0, $0.1, $0.2, $0.3) }))
        try write("c-side-page-error", page([], error: "magpie returned no usable quota rows for claude."))
        try write("c-side-page-no-history", page(used.map { named($0.0, $0.1, $0.2) }))
        try write("c-side-page-stale", page(
            used.map { named($0.0, $0.1, $0.2, $0.3) },
            error: "magpie refresh failed: The request timed out.",
            stale: true))
        try write(
            "d-footer",
            OverviewFooterView(
                autoRefreshOn: true,
                aboutHelp: "About CodexBar",
                quitHelp: "Quit",
                width: width)
                .padding(.vertical, 4))
    }
}
