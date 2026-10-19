import AppKit

/// Green / amber / red by used percent, for surfaces that show account health at a glance.
enum UsageSeverityPalette {
    static let amberThreshold: Double = 70
    static let redThreshold: Double = 90

    static func color(usedPercent: Double) -> NSColor {
        if usedPercent >= self.redThreshold { return .systemRed }
        if usedPercent >= self.amberThreshold { return .systemOrange }
        return .systemGreen
    }
}
