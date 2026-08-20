import AppKit
import QuartzCore

final class SettingsSidebarButton: NSButton {
    let page: SettingsContentView.Page

    private let iconMaterial = SettingsSidebarIconMaterialView()
    private let iconTintView = NSView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var isHovering = false
    private var trackingAreaReference: NSTrackingArea?

    init(title: String, symbol: String, page: SettingsContentView.Page) {
        self.page = page
        super.init(frame: .zero)
        self.title = ""
        identifier = NSUserInterfaceItemIdentifier("settings-navigation-\(page.identifier)")
        setButtonType(.toggle)
        isBordered = false
        isTransparent = true
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        let symbolImage = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: title
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        )

        iconMaterial.identifier = NSUserInterfaceItemIdentifier(
            "settings-navigation-icon-material-\(page.identifier)"
        )
        iconMaterial.material = .selection
        iconMaterial.blendingMode = .withinWindow
        iconMaterial.state = .active
        iconMaterial.wantsLayer = true
        iconMaterial.layer?.cornerRadius = 14
        iconMaterial.layer?.cornerCurve = .continuous
        iconMaterial.layer?.masksToBounds = true
        iconMaterial.translatesAutoresizingMaskIntoConstraints = false
        iconMaterial.setAccessibilityElement(false)
        addSubview(iconMaterial)

        iconTintView.identifier = NSUserInterfaceItemIdentifier(
            "settings-navigation-icon-tint-\(page.identifier)"
        )
        iconTintView.wantsLayer = true
        iconTintView.layer?.cornerRadius = 14
        iconTintView.layer?.cornerCurve = .continuous
        iconTintView.layer?.masksToBounds = true
        iconTintView.translatesAutoresizingMaskIntoConstraints = false
        iconTintView.setAccessibilityElement(false)
        iconMaterial.addSubview(iconTintView)

        iconView.image = symbolImage
        iconView.imageScaling = .scaleProportionallyDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setAccessibilityElement(false)
        iconMaterial.addSubview(iconView)

        titleLabel.stringValue = title
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(titleLabel)

        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(title)
        toolTip = title
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            iconMaterial.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconMaterial.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconMaterial.widthAnchor.constraint(equalToConstant: 28),
            iconMaterial.heightAnchor.constraint(equalToConstant: 28),
            iconTintView.leadingAnchor.constraint(equalTo: iconMaterial.leadingAnchor),
            iconTintView.trailingAnchor.constraint(equalTo: iconMaterial.trailingAnchor),
            iconTintView.topAnchor.constraint(equalTo: iconMaterial.topAnchor),
            iconTintView.bottomAnchor.constraint(equalTo: iconMaterial.bottomAnchor),
            iconView.centerXAnchor.constraint(equalTo: iconMaterial.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconMaterial.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: iconMaterial.trailingAnchor, constant: 10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
        ])
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool {
        state == .on
    }

    override func draw(_ dirtyRect: NSRect) {
        // The row's explicit icon and label avoid NSButtonCell redraw artifacts on glass.
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
        let titleColor: NSColor
        let iconColor: NSColor
        let iconTint: NSColor
        let rowTint: NSColor?
        if selected {
            titleColor = .labelColor
            iconColor = .selectedControlTextColor
            iconTint = SettingsContentView.pageAccentColor.withAlphaComponent(0.82)
            rowTint = SettingsContentView.pageAccentColor.withAlphaComponent(0.20)
        } else if isHovering {
            titleColor = .labelColor
            iconColor = .labelColor
            iconTint = NSColor.labelColor.withAlphaComponent(0.08)
            rowTint = NSColor.labelColor.withAlphaComponent(0.05)
        } else {
            titleColor = .secondaryLabelColor
            iconColor = .secondaryLabelColor
            iconTint = NSColor.labelColor.withAlphaComponent(0.04)
            rowTint = nil
        }

        iconView.contentTintColor = iconColor
        titleLabel.font = .systemFont(
            ofSize: 13,
            weight: selected ? .semibold : .medium
        )
        titleLabel.textColor = titleColor
        setAccessibilityValue(selected ? 1 : 0)
        var rowCGColor: CGColor?
        var iconCGColor: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            rowCGColor = rowTint?.cgColor
            iconCGColor = iconTint.cgColor
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = rowCGColor
        iconMaterial.layer?.backgroundColor = nil
        iconTintView.layer?.backgroundColor = iconCGColor
        CATransaction.commit()
    }
}

private final class SettingsSidebarIconMaterialView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
