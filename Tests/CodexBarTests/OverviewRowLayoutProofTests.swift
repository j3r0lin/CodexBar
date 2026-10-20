import AppKit
import CodexBarCore
import SwiftUI
import Testing
@testable import CodexBar

/// Opt-in render of the Overview rows and the footer bar on the dark menu background, for comparing
/// the app against `reports/preview-layout.html`.
@MainActor
struct OverviewRowLayoutProofTests {
    /// The width the app draws an Overview row at.
    private static let width = StatusItemController.overviewMenuMinimumWidth
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func `render overview rows and footer for the layout proof`() throws {
        guard let directory = ProcessInfo.processInfo.environment["CODEXBAR_OVERVIEW_ROW_PROOF_DIR"] else { return }
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let renderer = ImageRenderer(content: Self.column())
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: root.appendingPathComponent("overview-rows-dark.png"))

        let footer = MenuFooterBarView(width: Self.width, buttons: [
            MenuFooterButton(systemImageName: "arrow.clockwise", label: "Refresh", action: {}),
            MenuFooterButton(systemImageName: "gearshape", label: "Settings...", action: {}),
            MenuFooterButton(systemImageName: "info.circle", label: "About CodexBar", action: {}),
            MenuFooterButton(
                systemImageName: MenuDescriptor.MenuAction.quit.systemImageName ?? "",
                label: "Quit",
                action: {}),
        ])
        footer.appearance = NSAppearance(named: .darkAqua)
        footer.layoutSubtreeIfNeeded()
        let footerPNG = try #require(Self.bitmap(of: footer, scale: 2)?.representation(using: .png, properties: [:]))
        try footerPNG.write(to: root.appendingPathComponent("footer-dark.png"))
    }

    /// `dataWithPDF` drops layer backgrounds, so the menu colour is painted into the bitmap first.
    private static func bitmap(of view: NSView, scale: CGFloat) -> NSBitmapImageRep? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(view.bounds.width * scale),
            pixelsHigh: Int(view.bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)
        guard let rep, let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        self.menuBackground.setFill()
        view.bounds.fill()
        view.displayIgnoringOpacity(view.bounds, in: context)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static var menuBackground: NSColor {
        NSColor(srgbRed: 41 / 255, green: 41 / 255, blue: 42 / 255, alpha: 1)
    }

    /// The reference data set from the HTML preview: Codex 96/15, Claude a/b/c, Kimi Code, and a Grok
    /// row with only a 7d window.
    private static func column() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            self.row(
                name: "Codex",
                short: self.window(96, minutes: 2 * 60 + 20),
                long: self.window(15, minutes: 6 * 1440 + 21 * 60),
                namesProvider: true)
            self.row(
                name: "a",
                short: self.window(46, minutes: 18),
                long: self.window(95, minutes: 9 * 60 + 58),
                block: .single)
            self.row(
                name: "b",
                short: self.window(0, minutes: nil),
                long: self.window(84, minutes: 1440 + 9 * 60),
                block: .single)
            self.row(
                name: "c",
                short: self.window(0, minutes: nil),
                long: self.window(100, minutes: 2 * 60 + 58),
                block: .single)
            self.row(
                name: "Kimi Code",
                short: self.window(8, minutes: 4 * 1440 + 2 * 60),
                long: self.window(10, minutes: 52),
                namesProvider: true)
            self.row(
                name: "Grok",
                short: RateWindow(
                    usedPercent: 0,
                    windowMinutes: nil,
                    resetsAt: nil,
                    resetDescription: nil,
                    isSyntheticPlaceholder: true),
                long: self.window(90, minutes: 4 * 1440 + 20 * 60),
                namesProvider: true)
        }
        .frame(width: self.width)
        .background(Color(nsColor: self.menuBackground))
        .environment(\.colorScheme, .dark)
    }

    private static func row(
        name: String,
        short: RateWindow?,
        long: RateWindow?,
        block: OverviewBlockPosition = .single,
        namesProvider: Bool = true) -> some View
    {
        OverviewCompactAccountRow(
            name: name,
            shortWindow: short,
            longWindow: long,
            width: self.width,
            namesProvider: namesProvider,
            block: block,
            now: self.now)
    }

    private static func window(_ usedPercent: Double, minutes: Int?) -> RateWindow {
        RateWindow(
            usedPercent: usedPercent,
            windowMinutes: minutes,
            resetsAt: minutes.map { self.now.addingTimeInterval(TimeInterval($0 * 60)) },
            resetDescription: nil)
    }
}
