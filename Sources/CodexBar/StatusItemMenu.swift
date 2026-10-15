import AppKit
import CodexBarCore

protocol StatusItemMenuPersistentActionDelegate: AnyObject {
    func performPersistentRefreshAction(
        in menuID: ObjectIdentifier,
        menuInteractionGeneration: Int)
    func performPersistentSettingsAction()
    func performPersistentQuitAction()
}

final class StatusItemMenu: NSMenu {
    weak var persistentActionDelegate: StatusItemMenuPersistentActionDelegate?
    var menuInteractionGeneration: Int?

    func requestPersistentRefreshAction() {
        guard let menuInteractionGeneration else { return }
        self.persistentActionDelegate?.performPersistentRefreshAction(
            in: ObjectIdentifier(self),
            menuInteractionGeneration: menuInteractionGeneration)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let action = Self.persistentAction(for: event) {
            switch action {
            case .refresh:
                self.requestPersistentRefreshAction()
            case .settings:
                self.persistentActionDelegate?.performPersistentSettingsAction()
            case .quit:
                self.persistentActionDelegate?.performPersistentQuitAction()
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private enum PersistentAction {
        case refresh
        case settings
        case quit
    }

    nonisolated static func isPersistentRefreshShortcut(for event: NSEvent) -> Bool {
        self.persistentAction(for: event) == .refresh
    }

    private nonisolated static func persistentAction(for event: NSEvent) -> PersistentAction? {
        guard event.type == .keyDown else { return nil }

        let relevantModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard relevantModifiers == .command else { return nil }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "r":
            return .refresh
        case ",":
            return .settings
        case "q":
            return .quit
        default:
            return nil
        }
    }
}
