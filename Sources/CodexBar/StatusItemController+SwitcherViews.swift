import AppKit
import CodexBarCore
import QuartzCore

enum ProviderSwitcherSelection: Hashable {
    case overview
    case provider(ProviderInstanceID)
}

final class TokenAccountSwitcherView: NSView {
    private let accounts: [ProviderTokenAccount]
    private let onSelect: (Int) -> Task<Void, Never>?
    private var selectedIndex: Int
    private var buttons: [NSButton] = []
    private let preferredSize: NSSize
    private let rowSpacing: CGFloat = 4
    private let rowHeight: CGFloat = 26
    private let selectedBackground = NSColor.controlAccentColor.cgColor
    private let unselectedBackground = NSColor.clear.cgColor
    private let selectedTextColor = NSColor.white
    private let unselectedTextColor = NSColor.secondaryLabelColor

    init(
        accounts: [ProviderTokenAccount],
        selectedIndex: Int,
        width: CGFloat,
        onSelect: @escaping (Int) -> Task<Void, Never>?)
    {
        self.accounts = accounts
        self.onSelect = onSelect
        self.selectedIndex = min(max(selectedIndex, 0), max(0, accounts.count - 1))
        let useTwoRows = accounts.count > 3
        let rows = useTwoRows ? 2 : 1
        let height = self.rowHeight * CGFloat(rows) + (useTwoRows ? self.rowSpacing : 0)
        self.preferredSize = NSSize(width: width, height: height)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        self.wantsLayer = true
        self.buildButtons(useTwoRows: useTwoRows)
        self.updateButtonStyles()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        self.preferredSize
    }

    override var fittingSize: NSSize {
        self.preferredSize
    }

    private func buildButtons(useTwoRows: Bool) {
        let perRow = useTwoRows ? Int(ceil(Double(self.accounts.count) / 2.0)) : self.accounts.count
        let rows: [[ProviderTokenAccount]] = {
            if !useTwoRows { return [self.accounts] }
            let first = Array(self.accounts.prefix(perRow))
            let second = Array(self.accounts.dropFirst(perRow))
            return [first, second]
        }()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = self.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        var globalIndex = 0
        for rowAccounts in rows {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fillEqually
            row.spacing = self.rowSpacing
            row.translatesAutoresizingMaskIntoConstraints = false

            for account in rowAccounts {
                let button = PaddedToggleButton(
                    title: account.displayName,
                    target: self,
                    action: #selector(self.handleSelect))
                button.tag = globalIndex
                button.toolTip = account.displayName
                button.isBordered = false
                button.setButtonType(.toggle)
                button.controlSize = .small
                button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                button.cell?.lineBreakMode = account.displayName.contains("@") ? .byTruncatingMiddle : .byTruncatingTail
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                button.wantsLayer = true
                button.layer?.cornerRadius = 6
                row.addArrangedSubview(button)
                self.buttons.append(button)
                globalIndex += 1
            }

            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        self.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: self.topAnchor),
            stack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: self.rowHeight * CGFloat(rows.count) +
                (useTwoRows ? self.rowSpacing : 0)),
        ])
    }

    private func updateButtonStyles() {
        for (index, button) in self.buttons.enumerated() {
            let selected = index == self.selectedIndex
            button.state = selected ? .on : .off
            button.layer?.backgroundColor = selected ? self.selectedBackground : self.unselectedBackground
            button.contentTintColor = selected ? self.selectedTextColor : self.unselectedTextColor
        }
    }

    @objc private func handleSelect(_ sender: NSButton) {
        _ = self.select(index: sender.tag)
    }

    @discardableResult
    private func select(index: Int) -> Task<Void, Never>? {
        guard index >= 0, index < self.accounts.count else { return nil }
        self.selectedIndex = index
        self.updateButtonStyles()
        return self.onSelect(index)
    }

    #if DEBUG
    func _test_select(index: Int) -> Task<Void, Never>? {
        guard let button = self.buttons.first(where: { $0.tag == index }) else { return nil }
        return self.select(index: button.tag)
    }

    func _test_buttonTitles() -> [String] {
        self.buttons.map(\.title)
    }
    #endif
}
