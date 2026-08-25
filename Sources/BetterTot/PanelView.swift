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
    private(set) var dotColor: NSColor
    private var dotDescription: String

    var isSelectedPad = false {
        didSet { updatePresentation() }
    }

    init(pad: PadMetadata) {
        padIndex = pad.position
        dotColor = PanelContentView.padColor(for: pad)
        dotDescription = pad.accessibilityName
        super.init(frame: .zero)

        tag = pad.position
        identifier = NSUserInterfaceItemIdentifier("pad-dot-\(pad.position + 1)")
        title = ""
        imagePosition = .imageOnly
        imageScaling = .scaleNone
        isBordered = false
        refusesFirstResponder = true
        contentTintColor = dotColor
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 28),
            heightAnchor.constraint(equalToConstant: 28),
        ])
        updatePresentation()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func update(with pad: PadMetadata) {
        guard pad.position == padIndex else { return }
        dotColor = PanelContentView.padColor(for: pad)
        dotDescription = pad.accessibilityName
        contentTintColor = dotColor
        updatePresentation()
    }

    private func updatePresentation() {
        let symbol = isSelectedPad ? "circle.fill" : "circle"
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: dotDescription
        )?.withSymbolConfiguration(configuration)
        image?.accessibilityDescription = dotDescription
        toolTip = dotDescription
        setAccessibilityLabel(dotDescription)
        setAccessibilityValue(isSelectedPad ? "Selected" : "Not selected")
    }
}

final class PanelContentView: NSVisualEffectView {
    let closeButton: NSButton
    let padButtons: [PadDotButton]
    let pinButton: NSButton
    let settingsButton: NSButton
    let bulletedListButton: NSButton
    let numberedListButton: NSButton
    let checkboxListButton: NSButton
    let countsLabel = NSTextField(labelWithString: "")
    let saveIndicatorHost = NSView()
    let saveProgressIndicator = NSProgressIndicator()
    let saveIssueImageView = NSImageView()

    var onClose: (() -> Void)?
    var onSelectPad: ((Int) -> Void)?
    var onTogglePin: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onToggleBulletedList: (() -> Void)?
    var onToggleNumberedList: (() -> Void)?
    var onToggleCheckboxList: (() -> Void)?

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
        padButtons = pads.map { PadDotButton(pad: $0) }
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
        bulletedListButton = Self.toolbarButton(
            symbol: "list.bullet",
            label: "Bulleted list",
            identifier: "panel-bulleted-list"
        )
        numberedListButton = Self.toolbarButton(
            symbol: "list.number",
            label: "Numbered list",
            identifier: "panel-numbered-list"
        )
        checkboxListButton = Self.toolbarButton(
            symbol: "checklist",
            label: "Checkbox list",
            identifier: "panel-checkbox-list"
        )

        super.init(frame: .zero)
        material = .popover
        blendingMode = .behindWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        updateBorder()

        closeButton.target = self
        closeButton.action = #selector(closePressed)
        pinButton.target = self
        pinButton.action = #selector(pinPressed)
        settingsButton.target = self
        settingsButton.action = #selector(settingsPressed)
        bulletedListButton.target = self
        bulletedListButton.action = #selector(bulletedListPressed)
        numberedListButton.target = self
        numberedListButton.action = #selector(numberedListPressed)
        checkboxListButton.target = self
        checkboxListButton.action = #selector(checkboxListPressed)
        for button in padButtons {
            button.target = self
            button.action = #selector(padPressed(_:))
        }

        countsLabel.identifier = NSUserInterfaceItemIdentifier("panel-counts")
        countsLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countsLabel.textColor = .secondaryLabelColor
        countsLabel.alignment = .left
        countsLabel.lineBreakMode = .byTruncatingTail
        countsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        saveIndicatorHost.identifier = NSUserInterfaceItemIdentifier("panel-save-status")
        saveIndicatorHost.translatesAutoresizingMaskIntoConstraints = false
        saveIndicatorHost.setAccessibilityLabel("Local save status")

        saveProgressIndicator.identifier = NSUserInterfaceItemIdentifier("panel-save-spinner")
        saveProgressIndicator.style = .spinning
        saveProgressIndicator.controlSize = .small
        saveProgressIndicator.isIndeterminate = true
        saveProgressIndicator.isDisplayedWhenStopped = false
        saveProgressIndicator.translatesAutoresizingMaskIntoConstraints = false
        saveIndicatorHost.addSubview(saveProgressIndicator)

        saveIssueImageView.identifier = NSUserInterfaceItemIdentifier("panel-save-issue")
        saveIssueImageView.imageScaling = .scaleProportionallyDown
        saveIssueImageView.translatesAutoresizingMaskIntoConstraints = false
        saveIndicatorHost.addSubview(saveIssueImageView)

        NSLayoutConstraint.activate([
            saveIndicatorHost.widthAnchor.constraint(equalToConstant: 16),
            saveIndicatorHost.heightAnchor.constraint(equalToConstant: 16),
            saveProgressIndicator.centerXAnchor.constraint(
                equalTo: saveIndicatorHost.centerXAnchor
            ),
            saveProgressIndicator.centerYAnchor.constraint(
                equalTo: saveIndicatorHost.centerYAnchor
            ),
            saveProgressIndicator.widthAnchor.constraint(equalToConstant: 14),
            saveProgressIndicator.heightAnchor.constraint(equalToConstant: 14),
            saveIssueImageView.centerXAnchor.constraint(equalTo: saveIndicatorHost.centerXAnchor),
            saveIssueImageView.centerYAnchor.constraint(equalTo: saveIndicatorHost.centerYAnchor),
            saveIssueImageView.widthAnchor.constraint(equalToConstant: 14),
            saveIssueImageView.heightAnchor.constraint(equalToConstant: 14),
        ])

        let padStack = NSStackView(views: padButtons)
        padStack.orientation = .horizontal
        padStack.alignment = .centerY
        padStack.spacing = 3
        padStack.setAccessibilityLabel("Scratchpads")

        let leftSpacer = Self.flexibleSpacer()
        let rightSpacer = Self.flexibleSpacer()
        let header = NSStackView(views: [
            closeButton,
            leftSpacer,
            padStack,
            rightSpacer,
            pinButton,
        ])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6
        header.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        header.identifier = NSUserInterfaceItemIdentifier("panel-header")
        Self.applyChromeShade(to: header)
        header.setAccessibilityLabel("Panel controls")

        let footerSpacer = Self.flexibleSpacer()
        let footer = NSStackView(views: [
            countsLabel,
            saveIndicatorHost,
            footerSpacer,
            bulletedListButton,
            numberedListButton,
            checkboxListButton,
            settingsButton,
        ])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 6
        footer.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        footer.identifier = NSUserInterfaceItemIdentifier("panel-footer")
        Self.applyChromeShade(to: footer)
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
            header.heightAnchor.constraint(equalToConstant: 36),
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    func updateSelection(index: Int) {
        for button in padButtons {
            button.isSelectedPad = button.padIndex == index
        }
    }

    func updatePads(_ pads: [PadMetadata]) {
        let padsByPosition = Dictionary(uniqueKeysWithValues: pads.map { ($0.position, $0) })
        for button in padButtons {
            if let pad = padsByPosition[button.padIndex] {
                button.update(with: pad)
            }
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
        countsLabel.stringValue = "\(lines) lines · \(words) words · \(text.count) chars"
    }

    func setStatisticsVisible(_ visible: Bool) {
        countsLabel.isHidden = !visible
    }

    func updateSaveState(_ state: PanelSaveState) {
        saveProgressIndicator.stopAnimation(nil)
        saveProgressIndicator.isHidden = true
        saveIssueImageView.isHidden = true
        saveIndicatorHost.toolTip = state.label
        saveIndicatorHost.setAccessibilityValue(state.label)

        switch state {
        case .saving:
            saveProgressIndicator.isHidden = false
            saveProgressIndicator.startAnimation(nil)
        case .saved:
            break
        case .recoveryPending, .failed:
            let description = state == .failed ? "Save failed" : "Recovery saved"
            saveIssueImageView.image = Self.symbolImage(
                "exclamationmark.triangle.fill",
                label: description,
                pointSize: 13
            )
            saveIssueImageView.contentTintColor = state == .failed
                ? .systemRed
                : .systemOrange
            saveIssueImageView.isHidden = false
        }
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

    @objc private func bulletedListPressed() {
        onToggleBulletedList?()
    }

    @objc private func numberedListPressed() {
        onToggleNumberedList?()
    }

    @objc private func checkboxListPressed() {
        onToggleCheckboxList?()
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
            button.widthAnchor.constraint(equalToConstant: 28),
            button.heightAnchor.constraint(equalToConstant: 28),
        ])
        return button
    }

    private static func symbolImage(
        _ symbol: String,
        label: String,
        pointSize: CGFloat = 17
    ) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: pointSize,
            weight: .regular
        )
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

    private static func applyChromeShade(to view: NSView) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.16).cgColor
    }

    private func updateBorder() {
        layer?.backgroundColor = nil
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.borderWidth = 1
    }

    static func padColor(for pad: PadMetadata) -> NSColor {
        pad.resolvedColorIdentifier.color
    }
}
