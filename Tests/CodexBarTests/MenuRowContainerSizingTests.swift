import AppKit
import SwiftUI
import Testing
@testable import CodexBar

@MainActor
struct MenuRowContainerSizingTests {
    @Test
    func `fresh cached row publishes its measured height before first layout`() {
        let row = Self.makeRow(height: 40)

        row.applyMeasuredSize(width: 320, height: 123.2)

        #expect(row.frame.size == NSSize(width: 320, height: 124))
        #expect(row.intrinsicContentSize == NSSize(width: 320, height: 124))
        row.layoutSubtreeIfNeeded()
        #expect(row.intrinsicContentSize.height == 124)
    }

    @Test
    func `cached sibling keeps the same intrinsic height as a measured row`() {
        let measured = Self.makeRow(height: 145)
        let height = ceil(measured.measuredHeight(width: 320) + 7)
        measured.applyMeasuredSize(width: 320, height: height)
        let cached = Self.makeRow(height: 145)

        cached.applyMeasuredSize(width: 320, height: height)
        cached.layoutSubtreeIfNeeded()

        #expect(height == 152)
        #expect(measured.intrinsicContentSize.height == height)
        #expect(cached.intrinsicContentSize.height == height)
    }

    @Test
    func `replant discards the old measurement before accepting the incoming row size`() {
        let row = Self.makeRow(height: 40)
        row.applyMeasuredSize(width: 320, height: 124)

        row.replant(Self.payload(height: 72), refreshMonitor: nil)
        row.layoutSubtreeIfNeeded()

        #expect(row.intrinsicContentSize.height == 72)
        row.applyMeasuredSize(width: 320, height: 79)
        #expect(row.intrinsicContentSize.height == 79)
    }

    @Test
    func `width changes invalidate the measured height but frame height changes do not`() {
        let row = Self.makeRow(height: 40)
        row.applyMeasuredSize(width: 320, height: 124)

        row.setFrameSize(NSSize(width: 320, height: 1))
        #expect(row.intrinsicContentSize.height == 124)

        row.setFrameSize(NSSize(width: 400, height: 1))
        row.layoutSubtreeIfNeeded()
        #expect(row.intrinsicContentSize.height == 40)
        row.applyMeasuredSize(width: 400, height: 47)
        #expect(row.intrinsicContentSize == NSSize(width: 400, height: 47))
    }

    private static func makeRow(height: CGFloat) -> MenuRowContainerView {
        MenuRowContainerView(payload: self.payload(height: height), refreshMonitor: nil)
    }

    private static func payload(height: CGFloat) -> MenuCardRowPayload {
        MenuCardRowPayload(
            content: AnyView(Color.clear.frame(height: height)),
            showsSubmenuIndicator: false,
            submenuIndicatorAlignment: .topTrailing,
            submenuIndicatorTopPadding: 0,
            allowsMenuHighlight: false,
            containsInteractiveControls: false,
            usesGPUSelection: false,
            onClick: nil)
    }
}

@MainActor
struct MenuRowPanelBaseTests {
    private func row(usesPanelBase: Bool) -> MenuRowContainerView {
        let row = MenuRowContainerView(
            payload: MenuCardRowPayload(
                content: AnyView(Color.clear.frame(height: 20)),
                showsSubmenuIndicator: false,
                submenuIndicatorAlignment: .topTrailing,
                submenuIndicatorTopPadding: 0,
                allowsMenuHighlight: false,
                containsInteractiveControls: false,
                usesGPUSelection: false,
                usesPanelBase: usesPanelBase,
                onClick: nil),
            refreshMonitor: nil)
        row.applyMeasuredSize(width: 300, height: 40)
        row.layoutSubtreeIfNeeded()
        return row
    }

    private func panelLayerFrames(in row: MenuRowContainerView) -> [CGRect] {
        row.subviews.compactMap { view in
            guard let color = view.layer?.backgroundColor,
                  NSColor(cgColor: color)?.usingColorSpace(.sRGB) == OverviewPalette.panelBase.usingColorSpace(.sRGB)
            else { return nil }
            return view.frame
        }
    }

    @Test
    func `a panel row fills its whole frame with the opaque panel colour`() {
        let frames = self.panelLayerFrames(in: self.row(usesPanelBase: true))
        #expect(frames == [CGRect(x: 0, y: 0, width: 300, height: 40)])
        #expect(OverviewPalette.panelBase.alphaComponent == 1)
    }

    @Test
    func `a row outside the panel draws no panel colour`() {
        #expect(self.panelLayerFrames(in: self.row(usesPanelBase: false)).isEmpty)
    }

    @Test
    func `the panel is darker than the card surface`() throws {
        let panel = try #require(OverviewPalette.panelBase.usingColorSpace(.sRGB))
        let card = try #require(OverviewPalette.cardBase.usingColorSpace(.sRGB))
        #expect(panel.redComponent < card.redComponent)
        #expect(panel.alphaComponent > card.alphaComponent)
    }
}
