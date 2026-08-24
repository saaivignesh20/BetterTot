import AppKit

final class PadCustomizationView: NSView, NSTextFieldDelegate {
    let nameField = NSTextField()
    private(set) var padSelectorButtons: [SettingsPadSelectorButton] = []
    let colorSelector = NSPopUpButton(frame: .zero, pullsDown: false)

    var onUpdateRequested: ((PadID, String?, String?) -> Void)?

    private var pads = WorkspaceMetadata.fresh().pads.sorted { $0.position < $1.position }
    private var selectedPadID: PadID?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        selectedPadID = pads.first?.id
        build()
        render()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func updatePads(_ pads: [PadMetadata]) {
        let ordered = pads.sorted { $0.position < $1.position }
        guard !ordered.isEmpty else {
            setEditingEnabled(false)
            return
        }
        self.pads = ordered
        let candidate = selectedPadID
        selectedPadID = ordered.contains { $0.id == candidate } ? candidate : ordered[0].id
        render()
    }

    func setEditingEnabled(_ enabled: Bool) {
        nameField.isEnabled = enabled
        colorSelector.isEnabled = enabled
    }

    private var selectedPad: PadMetadata? {
        guard let selectedPadID else { return nil }
        return pads.first { $0.id == selectedPadID }
    }

    private func build() {
        nameField.identifier = NSUserInterfaceItemIdentifier("settings-pad-name")
        nameField.setAccessibilityLabel("Pad name")
        nameField.isEditable = true
        nameField.isSelectable = true
        nameField.isBezeled = true
        nameField.drawsBackground = true
        nameField.backgroundColor = .textBackgroundColor
        nameField.bezelStyle = .roundedBezel
        nameField.controlSize = .large
        nameField.focusRingType = .default
        nameField.font = .systemFont(ofSize: NSFont.systemFontSize(for: .large))
        nameField.maximumNumberOfLines = 1
        nameField.lineBreakMode = .byTruncatingTail
        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(commitName)
        NSLayoutConstraint.activate([
            nameField.widthAnchor.constraint(equalToConstant: 238),
            nameField.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
        ])

        padSelectorButtons = pads.map { pad in
            let button = SettingsPadSelectorButton(pad: pad)
            button.target = self
            button.action = #selector(selectPad(_:))
            return button
        }
        let padSelector = NSStackView(views: padSelectorButtons)
        padSelector.orientation = .horizontal
        padSelector.alignment = .centerY
        padSelector.spacing = 5
        padSelector.setAccessibilityElement(true)
        padSelector.setAccessibilityRole(.radioGroup)
        padSelector.setAccessibilityLabel("Scratchpads")

        colorSelector.identifier = NSUserInterfaceItemIdentifier("settings-pad-color")
        colorSelector.controlSize = .large
        colorSelector.imagePosition = .imageLeading
        colorSelector.target = self
        colorSelector.action = #selector(selectColor(_:))
        colorSelector.setAccessibilityRole(.popUpButton)
        colorSelector.setAccessibilityLabel("Pad color")
        colorSelector.widthAnchor.constraint(equalToConstant: 238).isActive = true
        configureColorMenu()

        let root = NSStackView(views: [
            labeledRow(title: "Pad", control: padSelector),
            separator(),
            labeledRow(title: "Name", control: nameField),
            separator(),
            labeledRow(title: "Color", control: colorSelector),
        ])
        root.orientation = .vertical
        root.alignment = .width
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: topAnchor),
            root.leadingAnchor.constraint(equalTo: leadingAnchor),
            root.trailingAnchor.constraint(equalTo: trailingAnchor),
            root.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func render() {
        guard let selectedPad else { return }
        let padsByPosition = Dictionary(uniqueKeysWithValues: pads.map { ($0.position, $0) })
        for button in padSelectorButtons {
            guard let pad = padsByPosition[button.padIndex] else { continue }
            button.update(with: pad, selected: pad.id == selectedPad.id)
        }
        nameField.stringValue = selectedPad.name ?? ""
        nameField.placeholderString = selectedPad.defaultName
        colorSelector.setAccessibilityLabel("\(selectedPad.accessibilityName) color")
        colorSelector.toolTip = "Color for \(selectedPad.accessibilityName)"
        if let item = colorSelector.itemArray.first(where: {
            $0.representedObject as? String == selectedPad.resolvedColorIdentifier.rawValue
        }) {
            colorSelector.select(item)
        }
    }

    private func configureColorMenu() {
        colorSelector.removeAllItems()
        for identifier in PadColorIdentifier.allCases {
            let item = NSMenuItem(
                title: identifier.displayName,
                action: nil,
                keyEquivalent: ""
            )
            item.identifier = NSUserInterfaceItemIdentifier(
                "settings-pad-color-\(identifier.rawValue)"
            )
            item.representedObject = identifier.rawValue
            item.image = Self.colorSwatchImage(for: identifier)
            item.toolTip = identifier.displayName
            colorSelector.menu?.addItem(item)
        }
    }

    private static func colorSwatchImage(for identifier: PadColorIdentifier) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { bounds in
            let circle = bounds.insetBy(dx: 2, dy: 2)
            identifier.color.setFill()
            NSBezierPath(ovalIn: circle).fill()
            NSColor.separatorColor.setStroke()
            let border = NSBezierPath(ovalIn: circle.insetBy(dx: 0.5, dy: 0.5))
            border.lineWidth = 1
            border.stroke()
            return true
        }
        image.isTemplate = false
        return image
    }

    private func requestUpdate(colorIdentifier: String?) {
        guard let selectedPad else { return }
        onUpdateRequested?(selectedPad.id, nameField.stringValue, colorIdentifier)
    }

    @objc private func selectPad(_ sender: SettingsPadSelectorButton) {
        guard let pad = pads.first(where: { $0.position == sender.padIndex }) else { return }
        selectedPadID = pad.id
        render()
    }

    @objc private func commitName() {
        guard let selectedPad,
              PadMetadata.normalizedName(nameField.stringValue) != selectedPad.name else {
            return
        }
        let preservedColor = selectedPad.colorIdentifier.flatMap {
            PadColorIdentifier(rawValue: $0.lowercased())?.rawValue
        }
        requestUpdate(colorIdentifier: preservedColor)
    }

    @objc private func selectColor(_ sender: NSPopUpButton) {
        guard let rawValue = sender.selectedItem?.representedObject as? String,
              let identifier = PadColorIdentifier(rawValue: rawValue) else {
            render()
            return
        }
        requestUpdate(colorIdentifier: identifier.rawValue)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitName()
    }

    private func labeledRow(title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.widthAnchor.constraint(equalToConstant: 52).isActive = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 10, right: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 54).isActive = true
        return row
    }

    private func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }
}

final class SettingsPadSelectorButton: NSButton {
    let padIndex: Int
    private var pad: PadMetadata
    private var selected = false

    init(pad: PadMetadata) {
        padIndex = pad.position
        self.pad = pad
        super.init(frame: .zero)
        tag = pad.position
        identifier = NSUserInterfaceItemIdentifier("settings-pad-selector-\(pad.position + 1)")
        title = String(pad.position + 1)
        isBordered = false
        focusRingType = .default
        wantsLayer = true
        layer?.cornerRadius = 16
        setAccessibilityRole(.radioButton)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 32),
            heightAnchor.constraint(equalToConstant: 32),
        ])
        update(with: pad, selected: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(with pad: PadMetadata, selected: Bool) {
        guard pad.position == padIndex else { return }
        self.pad = pad
        self.selected = selected
        state = selected ? .on : .off
        toolTip = pad.accessibilityName
        setAccessibilityLabel(pad.accessibilityName)
        setAccessibilityValue(selected ? "Selected" : "Not selected")
        updatePresentation()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePresentation()
    }

    private func updatePresentation() {
        let color = PanelContentView.padColor(for: pad)
        contentTintColor = color
        layer?.backgroundColor = color.withAlphaComponent(selected ? 0.92 : 0.22).cgColor
        layer?.borderColor = (
            selected ? NSColor.keyboardFocusIndicatorColor : color.withAlphaComponent(0.72)
        ).cgColor
        layer?.borderWidth = selected ? 2.5 : 1

        let textColor = selected ? Self.contrastingTextColor(for: color) : NSColor.labelColor
        attributedTitle = NSAttributedString(
            string: String(padIndex + 1),
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: textColor,
            ]
        )
    }

    private static func contrastingTextColor(for color: NSColor) -> NSColor {
        guard let rgb = color.usingColorSpace(.sRGB) else { return .white }
        let luminance = (0.2126 * rgb.redComponent)
            + (0.7152 * rgb.greenComponent)
            + (0.0722 * rgb.blueComponent)
        return luminance > 0.62 ? .black : .white
    }
}
