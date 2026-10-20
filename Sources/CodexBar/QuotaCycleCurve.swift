import CodexBarCore
import SwiftUI

/// A window's current cycle as magpie's tray panel draws it (app.js `quotaSpark`, `sparkGap`): what was
/// left over time, full at the top, against the even burn from full at the cycle's start to empty at its
/// reset. The gap between the two is shaded green where more is left than the even burn and amber where
/// less, so which side of the pace the window is on shows without reading an angle.
struct QuotaCycleCurve: View {
    let trend: OverviewUsageRow.Trend
    let now: Date
    var color: Color = OverviewPalette.accent

    var body: some View {
        Canvas { context, size in
            let start = self.trend.cycle.start
            let end = self.trend.cycle.reset ?? self.now
            let span = end.timeIntervalSince(start)
            guard span > 0 else { return }
            // One point of headroom keeps a full or empty reading's stroke inside the box.
            let width = size.width, top: CGFloat = 1, height = size.height - 2
            func x(_ date: Date) -> CGFloat {
                CGFloat(date.timeIntervalSince(start) / span) * width
            }
            func y(_ left: Double) -> CGFloat {
                top + height - CGFloat(min(100, max(0, left)) / 100) * height
            }

            if self.trend.cycle.reset != nil {
                let current = self.trend.current
                if let first = current.first, let last = current.last {
                    var gap = Path()
                    gap.move(to: CGPoint(x: x(first.at), y: y(first.left)))
                    for point in current.dropFirst() {
                        gap.addLine(to: CGPoint(x: x(point.at), y: y(point.left)))
                    }
                    // Back along the even burn, whose y at a time is its share of the cycle.
                    gap.addLine(to: CGPoint(x: x(last.at), y: top + height * x(last.at) / width))
                    gap.addLine(to: CGPoint(x: x(first.at), y: top + height * x(first.at) / width))
                    gap.closeSubpath()
                    let diagonalTop = CGPoint(x: 0, y: top), diagonalBottom = CGPoint(x: width, y: top + height)
                    let above = Path { path in
                        path.addLines([diagonalTop, CGPoint(x: width, y: top), diagonalBottom])
                        path.closeSubpath()
                    }
                    let below = Path { path in
                        path.addLines([diagonalTop, CGPoint(x: 0, y: top + height), diagonalBottom])
                        path.closeSubpath()
                    }
                    context.drawLayer { layer in
                        layer.clip(to: above)
                        layer.fill(gap, with: .color(OverviewPalette.reserve.opacity(0.26)))
                    }
                    context.drawLayer { layer in
                        layer.clip(to: below)
                        layer.fill(gap, with: .color(OverviewPalette.warning.opacity(0.32)))
                    }
                    let even = Path { path in
                        path.move(to: diagonalTop)
                        path.addLine(to: diagonalBottom)
                    }
                    context.stroke(
                        even,
                        with: .color(self.color.opacity(0.45)),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }

            var line = Path()
            var previous: MagpieQuotaHistoryPoint?
            for point in self.trend.readings {
                let position = CGPoint(x: x(point.at), y: y(point.left))
                if let previous, !MagpieQuotaTrend.cycleBreak(previous, point) {
                    line.addLine(to: position)
                } else {
                    line.move(to: position)
                }
                previous = point
            }
            context.stroke(
                line,
                with: .color(self.color),
                style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
