import AppKit

final class PadCustomizationView: NSView, NSTextFieldDelegate {
    let nameField = NSTextField()
    private(set) var padSelectorButtons: [SettingsPadSelectorButton] = []
    private(set) var colorButtons: [PadColorSwatchButton] = []

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
        colorButtons.forEach { $0.isEnabled = enabled }
    }

    private var selectedPad: PadMetadata? {
        guard let selectedPadID else { return nil }
        return pads.first { $0.id == selectedPadID }
    }

    private func build() {
        nameField.identifier = NSUserInterfaceItemIdentifier("settings-pad-name")
        nameField.setAccessibilityLabel("Pad name")
        nameField.maximumNumberOfLines = 1
        nameField.lineBreakMode = .byTruncatingTail
        nameField.delegate = self
        nameField.target = self
        nameField.action = #selector(commitName)
        nameField.widthAnchor.constraint(equalToConstant: 238).isActive = true

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

        colorButtons = PadColorIdentifier.allCases.map { identifier in
            let button = PadColorSwatchButton(identifier: identifier)
            button.target = self
            button.action = #selector(selectColor(_:))
            return button
        }
        let colors = NSStackView(views: colorButtons)
        colors.orientation = .horizontal
        colors.alignment = .centerY
        colors.spacing = 5
        colors.setAccessibilityElement(true)
        colors.setAccessibilityRole(.radioGroup)
        colors.setAccessibilityLabel("Pad color")

        let root = NSStackView(views: [
            labeledRow(title: "Pad", control: padSelector),
            separator(),
            labeledRow(title: "Name", control: nameField),
            separator(),
            labeledRow(title: "Color", control: colors),
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
        for button in colorButtons {
            button.state = button.colorIdentifier == selectedPad.resolvedColorIdentifier
                ? .on
                : .off
        }
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

    @objc private func selectColor(_ sender: PadColorSwatchButton) {
        for button in colorButtons {
            button.state = button === sender ? .on : .off
        }
        requestUpdate(colorIdentifier: sender.colorIdentifier.rawValue)
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

    init(pad: PadMetadata) {
        padIndex = pad.position
        super.init(frame: .zero)
        tag = pad.position
        identifier = NSUserInterfaceItemIdentifier("settings-pad-selector-\(pad.position + 1)")
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        isBordered = false
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
        state = selected ? .on : .off
        let symbol = selected ? "circle.fill" : "circle"
        image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: pad.accessibilityName
        )?.withSymbolConfiguration(.init(pointSize: 18, weight: .medium))
        contentTintColor = PanelContentView.padColor(for: pad)
        toolTip = pad.accessibilityName
        setAccessibilityLabel(pad.accessibilityName)
        setAccessibilityValue(selected ? "Selected" : "Not selected")
    }
}

final class PadColorSwatchButton: NSButton {
    let colorIdentifier: PadColorIdentifier

    override var state: NSControl.StateValue {
        didSet { updateImage() }
    }

    init(identifier: PadColorIdentifier) {
        colorIdentifier = identifier
        super.init(frame: .zero)
        self.identifier = NSUserInterfaceItemIdentifier(
            "settings-pad-color-\(identifier.rawValue)"
        )
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        isBordered = false
        contentTintColor = identifier.color
        toolTip = identifier.displayName
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(identifier.displayName)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 32),
            heightAnchor.constraint(equalToConstant: 32),
        ])
        updateImage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func updateImage() {
        let symbol = state == .on ? "checkmark.circle.fill" : "circle.fill"
        image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: colorIdentifier.displayName
        )?.withSymbolConfiguration(.init(pointSize: 20, weight: .medium))
        setAccessibilityValue(state == .on ? "Selected" : "Not selected")
    }
}
