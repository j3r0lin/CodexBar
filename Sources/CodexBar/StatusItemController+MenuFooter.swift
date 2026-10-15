import AppKit

private enum MenuFooterBarRegistry {
    /// Footer bars are weakly tracked so a refresh started while the menu is open can spin their icon.
    static let bars = NSMapTable<StatusItemController, NSHashTable<MenuFooterBarView>>.weakToStrongObjects()
}

extension StatusItemController {
    var menuFooterBars: NSHashTable<MenuFooterBarView> {
        if let existing = MenuFooterBarRegistry.bars.object(forKey: self) {
            return existing
        }
        let created = NSHashTable<MenuFooterBarView>.weakObjects()
        MenuFooterBarRegistry.bars.setObject(created, forKey: self)
        return created
    }

    /// The four trailing meta actions collapse into one icon bar. Their keyboard shortcuts stay
    /// with `StatusItemMenu.performKeyEquivalent`: a hidden item's keyEquivalent does not fire
    /// while a menu is tracking, even with `allowsKeyEquivalentWhenHidden`.
    private func appendMenuFooterBarIfNeeded(
        entry: MenuDescriptor.Entry,
        section: MenuDescriptor.Section,
        to menu: NSMenu,
        width: CGFloat,
        captureMenu: NSMenu?) -> Bool
    {
        guard case let .action(_, action) = entry, Self.menuFooterActions.contains(action) else { return false }
        guard menu.items.last?.view as? MenuFooterBarView == nil else { return true }

        let actions = section.entries.compactMap { entry -> MenuDescriptor.MenuAction? in
            guard case let .action(_, action) = entry, Self.menuFooterActions.contains(action) else { return nil }
            return action
        }
        let buttons = actions.map { action in
            self.menuFooterButton(for: action, menu: captureMenu ?? menu)
        }
        let bar = MenuFooterBarView(width: width, buttons: buttons)
        let item = NSMenuItem()
        item.view = bar
        item.representedObject = Self.menuFooterBarItemID
        menu.addItem(item)
        self.menuFooterBars.add(bar)
        self.updateMenuFooterBars()
        return true
    }

    private func menuFooterButton(for action: MenuDescriptor.MenuAction, menu: NSMenu?) -> MenuFooterButton {
        MenuFooterButton(
            systemImageName: action.systemImageName ?? "",
            label: self.menuFooterLabel(for: action))
        { [weak self, weak menu] in
            guard let self else { return }
            self.performMenuFooterAction(action, menu: menu)
        }
    }

    private func menuFooterLabel(for action: MenuDescriptor.MenuAction) -> String {
        switch action {
        case .refresh: L("Refresh")
        case .settings: L("Settings...")
        case .about: L("About CodexBar") + (AppVersion.shortVersion.isEmpty ? "" : " (v\(AppVersion.shortVersion))")
        case .quit: L("Quit")
        default: ""
        }
    }

    private func performMenuFooterAction(_ action: MenuDescriptor.MenuAction, menu: NSMenu?) {
        switch action {
        case .refresh:
            if let menu = menu as? StatusItemMenu {
                menu.requestPersistentRefreshAction()
            } else if let menu {
                self.performPersistentRefreshAction(in: ObjectIdentifier(menu))
            }
        case .settings:
            menu?.cancelTracking()
            self.showSettingsGeneral()
        case .about:
            menu?.cancelTracking()
            self.showSettingsAbout()
        case .quit:
            menu?.cancelTracking()
            self.quit()
        default:
            break
        }
    }
}
