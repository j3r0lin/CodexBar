import AppKit
import CodexBarCore

extension StatusItemController {
    /// The store-icon signature ignores magpie accounts, so the rings follow the account list on their own.
    func observeClaudeAccountRings() {
        withObservationTracking {
            _ = self.store.claudeAccountSource.accounts
            _ = self.settings.hidePersonalInfo
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.observeClaudeAccountRings()
                self.updateClaudeAccountRingItems()
            }
        }
        self.updateClaudeAccountRingItems()
    }

    func updateClaudeAccountRingItems() {
        let accounts = self.claudeAccountTabsEnabled ? self.store.claudeAccountSource.accounts : []
        let liveIDs = Set(accounts.map(\.id))
        for (id, item) in self.claudeAccountRingItems where !liveIDs.contains(id) {
            NSStatusBar.system.removeStatusItem(item)
            self.claudeAccountRingItems.removeValue(forKey: id)
            self.claudeAccountRingHover.removeValue(forKey: id)
        }
        let hidePersonalInfo = self.settings.hidePersonalInfo
        for account in accounts {
            let item = self.claudeAccountRingItems[account.id] ?? {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.target = self
                item.button?.action = #selector(self.handleClaudeAccountRingClick(_:))
                item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                if let button = item.button {
                    let tracker = ClaudeAccountRingHoverTracker(accountID: account.id) { [weak self] id in
                        self?.showClaudeAccountHover(id)
                    }
                    button.addTrackingArea(NSTrackingArea(
                        rect: .zero,
                        options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                        owner: tracker,
                        userInfo: nil))
                    self.claudeAccountRingHover[account.id] = tracker
                }
                self.claudeAccountRingItems[account.id] = item
                return item
            }()
            guard let button = item.button else { continue }
            let usedPercent = Self.claudeAccountUsedPercent(account)
            let name = Self.claudeAccountShortName(account, hidePersonalInfo: hidePersonalInfo)
            button.identifier = NSUserInterfaceItemIdentifier(account.id.opaqueID)
            button.image = ClaudeAccountRingImage.make(
                usedPercent: usedPercent,
                refreshPhase: self.claudeAccountRefreshAnimation?.phase(for: account.id))
            button.imagePosition = .imageLeft
            button.attributedTitle = NSAttributedString(
                string: " " + name,
                attributes: [.font: NSFont.menuBarFont(ofSize: 11)])
        }
    }

    @objc func handleClaudeAccountRingClick(_ sender: NSStatusBarButton) {
        guard let account = self.store.claudeAccountSource.accounts
            .first(where: { $0.id.opaqueID == sender.identifier?.rawValue })
        else { return }
        self.claudeAccountHoverPanel.hide()
        if NSApp.currentEvent?.type == .rightMouseUp {
            self.refreshClaudeAccountFromRing(account.id)
            return
        }
        self.selectClaudeAccountTab(account.id)
        self.selectedMenuProvider = UsageProvider.claude.instanceID
        self.lastMenuProvider = UsageProvider.claude.instanceID
        self.settings.mergedMenuLastSelectedWasOverview = false
        self.lastMergedSwitcherSelection = .provider(UsageProvider.claude.instanceID)
        self.invalidateMenus()
        let menu = self.shouldMergeIcons ? (self.mergedMenu ?? self.makeMenu()) : self.makeMenu(for: .claude)
        // Anchor under the ring that was clicked rather than under the main status item.
        let y: CGFloat = sender.isFlipped ? sender.bounds.maxY + 4 : -4
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: y), in: sender)
    }

    /// magpie serves every account from one quotas call, so refreshing one account refreshes the source.
    private func refreshClaudeAccountFromRing(_ id: ProviderAccountIdentity) {
        let animation = self.claudeAccountRefreshAnimation ?? ClaudeAccountRingRefreshAnimation { [weak self] in
            self?.updateClaudeAccountRingItems()
        }
        self.claudeAccountRefreshAnimation = animation
        animation.begin(id)
        Task { @MainActor [weak self] in
            await self?.store.refreshClaudeMagpieAccounts()
            animation.end(id)
        }
    }

    private func showClaudeAccountHover(_ id: ProviderAccountIdentity) {
        guard self.openMenus.isEmpty,
              let button = self.claudeAccountRingItems[id]?.button,
              let account = self.store.claudeAccountSource.accounts.first(where: { $0.id == id })
        else { return }
        let name = "Claude · " + Self.claudeAccountShortName(account, hidePersonalInfo: self.settings.hidePersonalInfo)
        self.claudeAccountHoverPanel.show(
            ClaudeAccountHoverCard(name: name, snapshot: account.snapshot),
            below: button,
            isSuppressed: { [weak self] in !(self?.openMenus.isEmpty ?? true) })
    }
}

final class ClaudeAccountRingHoverTracker: NSResponder {
    let accountID: ProviderAccountIdentity
    private let onEnter: (ProviderAccountIdentity) -> Void

    init(accountID: ProviderAccountIdentity, onEnter: @escaping (ProviderAccountIdentity) -> Void) {
        self.accountID = accountID
        self.onEnter = onEnter
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func mouseEntered(with event: NSEvent) {
        self.onEnter(self.accountID)
    }
}

/// Spins a bright segment on each refreshing ring; held at least 650 ms so a fast refresh still reads.
@MainActor
final class ClaudeAccountRingRefreshAnimation {
    private var startedAt: [ProviderAccountIdentity: Date] = [:]
    private var pendingEnd: Set<ProviderAccountIdentity> = []
    private var timer: Timer?
    private let redraw: () -> Void
    private static let minimumDuration: TimeInterval = 0.65

    init(redraw: @escaping () -> Void) {
        self.redraw = redraw
    }

    func phase(for id: ProviderAccountIdentity) -> Double? {
        guard let start = self.startedAt[id] else { return nil }
        return Date().timeIntervalSince(start).truncatingRemainder(dividingBy: 0.9) / 0.9
    }

    func begin(_ id: ProviderAccountIdentity) {
        self.startedAt[id] = self.startedAt[id] ?? Date()
        self.pendingEnd.remove(id)
        guard self.timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func end(_ id: ProviderAccountIdentity) {
        self.pendingEnd.insert(id)
    }

    private func tick() {
        let now = Date()
        for id in self.pendingEnd {
            if let start = self.startedAt[id], now.timeIntervalSince(start) >= Self.minimumDuration {
                self.startedAt.removeValue(forKey: id)
                self.pendingEnd.remove(id)
            }
        }
        if self.startedAt.isEmpty {
            self.timer?.invalidate()
            self.timer = nil
        }
        self.redraw()
    }
}

enum ClaudeAccountRingImage {
    static func make(usedPercent: Double?, refreshPhase: Double? = nil) -> NSImage {
        let size = NSSize(width: 15, height: 15)
        return NSImage(size: size, flipped: false) { rect in
            let lineWidth: CGFloat = 2.5
            let ringRect = rect.insetBy(dx: lineWidth / 2 + 0.5, dy: lineWidth / 2 + 0.5)
            let track = NSBezierPath(ovalIn: ringRect)
            track.lineWidth = lineWidth
            NSColor.labelColor.withAlphaComponent(0.25).setStroke()
            track.stroke()
            let center = NSPoint(x: rect.midX, y: rect.midY)
            if let refreshPhase {
                let start = 90 - 360 * refreshPhase
                let spinner = NSBezierPath()
                spinner.appendArc(
                    withCenter: center,
                    radius: ringRect.width / 2,
                    startAngle: start,
                    endAngle: start - 80,
                    clockwise: true)
                spinner.lineWidth = lineWidth
                spinner.lineCapStyle = .round
                NSColor.labelColor.setStroke()
                spinner.stroke()
                return true
            }
            guard let usedPercent else { return true }
            let fraction = max(0, min(1, usedPercent / 100))
            guard fraction > 0 else { return true }
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
