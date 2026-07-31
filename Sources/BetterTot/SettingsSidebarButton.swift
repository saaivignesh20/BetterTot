import AppKit

final class SettingsSidebarButton: NSButton {
    let page: SettingsContentView.Page

    private var isHovering = false
    private var trackingAreaReference: NSTrackingArea?

    init(title: String, symbol: String, page: SettingsContentView.Page) {
        self.page = page
        super.init(frame: .zero)
        self.title = title
        identifier = NSUserInterfaceItemIdentifier("settings-navigation-\(page.identifier)")
        setButtonType(.toggle)
        isBordered = false
        alignment = .left
        image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: title
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        )
        imagePosition = .imageLeading
        imageHugsTitle = true
        wantsLayer = true
        layer?.cornerRadius = 7
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
        heightAnchor.constraint(equalToConstant: 36).isActive = true
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool {
        state == .on
    }

    override var state: NSControl.StateValue {
        didSet { updateAppearance() }
    }

    override func keyDown(with event: NSEvent) {
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(blockedModifiers).isEmpty else {
            super.keyDown(with: event)
            return
        }

        switch event.keyCode {
        case 123, 126:
            moveSelection(by: -1)
        case 124, 125:
            moveSelection(by: 1)
        default:
            super.keyDown(with: event)
        }
    }

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        trackingAreaReference = tracking
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        updateAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func moveSelection(by offset: Int) {
        guard let stack = superview as? NSStackView else { return }
        let buttons = stack.arrangedSubviews.compactMap { $0 as? SettingsSidebarButton }
        guard let index = buttons.firstIndex(of: self), !buttons.isEmpty else { return }

        let destination = (index + offset + buttons.count) % buttons.count
        let button = buttons[destination]
        button.performClick(nil)
        window?.makeFirstResponder(button)
    }

    private func updateAppearance() {
        let selected = state == .on
        let foreground = selected ? NSColor.controlAccentColor : NSColor.labelColor
        let background: NSColor
        if selected {
            background = NSColor.controlAccentColor.withAlphaComponent(0.17)
        } else if isHovering {
            background = NSColor.labelColor.withAlphaComponent(0.07)
        } else {
            background = .clear
        }

        contentTintColor = foreground
        setAccessibilityValue(selected ? 1 : 0)
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(
                    ofSize: 13,
                    weight: selected ? .semibold : .medium
                ),
                .foregroundColor: foreground,
            ]
        )
        layer?.backgroundColor = background.cgColor
    }
}
