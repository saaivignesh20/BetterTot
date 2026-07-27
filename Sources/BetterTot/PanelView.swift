import AppKit

enum PanelSaveState: Equatable {
    case saving
    case saved
    case recoveryPending
    case failed

    var label: String {
        switch self {
        case .saving: "Saving…"
        case .saved: "Saved"
        case .recoveryPending: "Recovery saved"
        case .failed: "Save failed"
        }
    }

    static func resolve(committed: Bool, journaled: Bool) -> PanelSaveState {
        if committed { return .saved }
        return journaled ? .recoveryPending : .failed
    }
}

final class PadDotButton: NSButton {
    let padIndex: Int
    let dotColor: NSColor

    var isSelectedPad = false {
        didSet { updatePresentation() }
    }

    init(index: Int, color: NSColor) {
        padIndex = index
        dotColor = color
        super.init(frame: .zero)

        tag = index
        identifier = NSUserInterfaceItemIdentifier("pad-dot-\(index + 1)")
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        isBordered = false
        refusesFirstResponder = true
        toolTip = "Scratchpad \(index + 1)"
        setAccessibilityLabel("Scratchpad \(index + 1)")
        contentTintColor = color
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 32),
            heightAnchor.constraint(equalToConstant: 32),
        ])
        updatePresentation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func updatePresentation() {
        let description = "Scratchpad \(padIndex + 1)"
        let symbol = isSelectedPad ? "circle.fill" : "circle"
        let configuration = NSImage.SymbolConfiguration(pointSize: 19, weight: .medium)
        image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: description
        )?.withSymbolConfiguration(configuration)
        image?.accessibilityDescription = description
        setAccessibilityValue(isSelectedPad ? "Selected" : "Not selected")
    }
}

final class PanelContentView: NSVisualEffectView {
    let closeButton: NSButton
    let padButtons: [PadDotButton]
    let pinButton: NSButton
    let settingsButton: NSButton
    let countsLabel = NSTextField(labelWithString: "")
    let saveStatusLabel = NSTextField(labelWithString: "")

    var onClose: (() -> Void)?
    var onSelectPad: ((Int) -> Void)?
    var onTogglePin: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    private let footerDot = NSImageView()

    init(
        scrollView: NSScrollView,
        pads: [PadMetadata],
        selectedIndex: Int
    ) {
        closeButton = Self.toolbarButton(
            symbol: "xmark.circle",
            label: "Close",
            identifier: "panel-close"
        )
        padButtons = pads.map {
            PadDotButton(index: $0.position, color: Self.padColor(for: $0))
        }
        pinButton = Self.toolbarButton(
            symbol: "pin",
            label: "Pin",
            identifier: "panel-pin"
        )
        settingsButton = Self.toolbarButton(
            symbol: "gearshape",
            label: "Settings",
            identifier: "panel-settings"
        )

        super.init(frame: .zero)

        material = .popover
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true

        closeButton.target = self
        closeButton.action = #selector(closePressed)
        pinButton.target = self
        pinButton.action = #selector(pinPressed)
        settingsButton.target = self
        settingsButton.action = #selector(settingsPressed)
        for button in padButtons {
            button.target = self
            button.action = #selector(padPressed(_:))
        }

        countsLabel.identifier = NSUserInterfaceItemIdentifier("panel-counts")
        countsLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countsLabel.textColor = .secondaryLabelColor
        countsLabel.lineBreakMode = .byTruncatingTail
        countsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        saveStatusLabel.identifier = NSUserInterfaceItemIdentifier("panel-save-status")
        saveStatusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        saveStatusLabel.textColor = .secondaryLabelColor
        saveStatusLabel.alignment = .right
        saveStatusLabel.setContentHuggingPriority(.required, for: .horizontal)

        footerDot.image = NSImage(
            systemSymbolName: "circle.fill",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: 8, weight: .regular))
        footerDot.imageScaling = .scaleNone
        footerDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            footerDot.widthAnchor.constraint(equalToConstant: 12),
            footerDot.heightAnchor.constraint(equalToConstant: 12),
        ])

        let padStack = NSStackView(views: padButtons)
        padStack.orientation = .horizontal
        padStack.alignment = .centerY
        padStack.spacing = 3
        padStack.setAccessibilityLabel("Scratchpads")

        let leftSpacer = Self.flexibleSpacer()
        let rightSpacer = Self.flexibleSpacer()
        let leftControlSpacer = NSView()
        leftControlSpacer.translatesAutoresizingMaskIntoConstraints = false
        leftControlSpacer.widthAnchor.constraint(equalToConstant: 32).isActive = true
        let leftControls = NSStackView(views: [closeButton, leftControlSpacer])
        leftControls.orientation = .horizontal
        leftControls.spacing = 6
        let rightControls = NSStackView(views: [pinButton, settingsButton])
        rightControls.orientation = .horizontal
        rightControls.spacing = 6
        let header = NSStackView(views: [
            leftControls,
            leftSpacer,
            padStack,
            rightSpacer,
            rightControls,
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)
        header.setAccessibilityLabel("Panel controls")

        let footerSpacer = Self.flexibleSpacer()
        let footer = NSStackView(views: [
            footerDot,
            countsLabel,
            footerSpacer,
            saveStatusLabel,
        ])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 6
        footer.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)

        let topSeparator = Self.separator()
        let bottomSeparator = Self.separator()
        let root = NSStackView(views: [
            header,
            topSeparator,
            scrollView,
            bottomSeparator,
            footer,
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
            header.heightAnchor.constraint(equalToConstant: 46),
            footer.heightAnchor.constraint(equalToConstant: 34),
            leftSpacer.widthAnchor.constraint(equalTo: rightSpacer.widthAnchor),
        ])

        updateSelection(index: selectedIndex)
        updatePinned(false)
        updateTextStatistics("")
        updateSaveState(.saved)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func updateSelection(index: Int) {
        for button in padButtons {
            button.isSelectedPad = button.padIndex == index
        }
        if padButtons.indices.contains(index) {
            footerDot.contentTintColor = padButtons[index].dotColor
        }
    }

    func updatePinned(_ pinned: Bool) {
        let label = pinned ? "Unpin" : "Pin"
        let symbol = pinned ? "pin.fill" : "pin"
        pinButton.image = Self.symbolImage(symbol, label: "\(label) panel")
        pinButton.toolTip = label
        pinButton.setAccessibilityLabel("\(label) panel")
        pinButton.setAccessibilityValue(pinned ? "Pinned" : "Not pinned")
    }

    func updateTextStatistics(_ text: String) {
        let lines = text.isEmpty ? 0 : text.reduce(1) { count, character in
            count + (character == "\n" ? 1 : 0)
        }
        var words = 0
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in
            words += 1
        }
        countsLabel.stringValue = "\(lines) lines · \(words) words · \(text.count) characters"
    }

    func updateSaveState(_ state: PanelSaveState) {
        saveStatusLabel.stringValue = state.label
        saveStatusLabel.textColor = state == .failed ? .systemRed : .secondaryLabelColor
        saveStatusLabel.setAccessibilityLabel("Local save status: \(state.label)")
    }

    @objc private func closePressed() {
        onClose?()
    }

    @objc private func padPressed(_ sender: PadDotButton) {
        onSelectPad?(sender.padIndex)
    }

    @objc private func pinPressed() {
        onTogglePin?()
    }

    @objc private func settingsPressed() {
        onOpenSettings?()
    }

    private static func toolbarButton(
        symbol: String,
        label: String,
        identifier: String
    ) -> NSButton {
        let image = symbolImage(symbol, label: label)
        let button = NSButton(image: image, target: nil, action: nil)
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.isBordered = false
        button.refusesFirstResponder = true
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 32),
            button.heightAnchor.constraint(equalToConstant: 32),
        ])
        return button
    }

    private static func symbolImage(_ symbol: String, label: String) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        return NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: label
        )?.withSymbolConfiguration(configuration) ?? NSImage()
    }

    private static func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private static func separator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    private static func padColor(for pad: PadMetadata) -> NSColor {
        let named: [String: NSColor] = [
            "red": .systemRed,
            "orange": .systemOrange,
            "yellow": .systemYellow,
            "green": .systemGreen,
            "teal": .systemTeal,
            "blue": .systemBlue,
            "purple": .systemPurple,
        ]
        if let identifier = pad.colorIdentifier?.lowercased(),
           let color = named[identifier] {
            return color
        }
        let palette: [NSColor] = [
            .systemYellow,
            .systemOrange,
            .systemRed,
            .systemPurple,
            .systemBlue,
            .systemTeal,
            .systemGreen,
        ]
        return palette[pad.position % palette.count]
    }
}
