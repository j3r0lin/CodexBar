import AppKit
import CodexBarCore

extension StatusItemController {
    func updateClaudeAccountRingItems() {
        let accounts = self.claudeAccountTabsEnabled ? self.store.claudeAccountSource.accounts : []
        let liveIDs = Set(accounts.map(\.id))
        for (id, item) in self.claudeAccountRingItems where !liveIDs.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            self.claudeAccountRingItems.removeValue(forKey: id)
        }
        let hidePersonalInfo = self.settings.hidePersonalInfo
        for account in accounts {
            let item = self.claudeAccountRingItems[account.id] ?? {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.target = self
                item.button?.action = #selector(self.handleClaudeAccountRingClick(_:))
                self.claudeAccountRingItems[account.id] = item
                return item
            }()
            guard let button = item.button else { continue }
            let usedPercent = Self.claudeAccountUsedPercent(account)
            let name = Self.claudeAccountShortName(account, hidePersonalInfo: hidePersonalInfo)
            button.identifier = NSUserInterfaceItemIdentifier(account.id.opaqueID)
            button.image = ClaudeAccountRingImage.make(usedPercent: usedPercent)
            button.imagePosition = .imageLeft
            button.attributedTitle = NSAttributedString(
                string: " " + name,
                attributes: [.font: NSFont.menuBarFont(ofSize: 11)])
            button.toolTip = usedPercent.map { "\(name) · \(Int($0.rounded()))%" } ?? name
        }
    }

    @objc func handleClaudeAccountRingClick(_ sender: NSStatusBarButton) {
        guard let account = self.store.claudeAccountSource.accounts
            .first(where: { $0.id.opaqueID == sender.identifier?.rawValue })
        else { return }
        self.selectClaudeAccountTab(account.id)
        self.selectedMenuProvider = UsageProvider.claude.instanceID
        self.lastMenuProvider = UsageProvider.claude.instanceID
        self.settings.mergedMenuLastSelectedWasOverview = false
        self.lastMergedSwitcherSelection = .provider(UsageProvider.claude.instanceID)
        self.invalidateMenus()
        if self.shouldMergeIcons {
            self.statusItem.button?.performClick(nil)
        } else {
            self.lazyStatusItem(for: .claude).button?.performClick(nil)
        }
    }
}

enum ClaudeAccountRingImage {
    static func make(usedPercent: Double?) -> NSImage {
        let size = NSSize(width: 15, height: 15)
        return NSImage(size: size, flipped: false) { rect in
            let lineWidth: CGFloat = 2.5
            let ringRect = rect.insetBy(dx: lineWidth / 2 + 0.5, dy: lineWidth / 2 + 0.5)
            let track = NSBezierPath(ovalIn: ringRect)
            track.lineWidth = lineWidth
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            track.stroke()
            guard let usedPercent else { return true }
            let fraction = max(0, min(1, usedPercent / 100))
            guard fraction > 0 else { return true }
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let arc = NSBezierPath()
            arc.appendArc(
                withCenter: center,
                radius: ringRect.width / 2,
                startAngle: 90,
                endAngle: 90 - 360 * fraction,
                clockwise: true)
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .round
            UsageSeverityPalette.color(usedPercent: usedPercent).setStroke()
            arc.stroke()
            return true
        }
    }
}
