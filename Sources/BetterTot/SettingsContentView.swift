import AppKit

final class SettingsContentView: NSVisualEffectView {
    enum Page: Int, CaseIterable {
        case general
        case editor
        case storage
        case updates

        var title: String {
            switch self {
            case .general: "General"
            case .editor: "Editor"
            case .storage: "Storage"
            case .updates: "Updates"
            }
        }

        var identifier: String {
            title.lowercased()
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .editor: "textformat"
            case .storage: "externaldrive"
            case .updates: "arrow.triangle.2.circlepath"
            }
        }
    }

    let navigation: NSSegmentedControl
    let launchAtLogin = NSSwitch()
    let spellChecking = NSSwitch()
    let smartQuotes = NSSwitch()
    let smartDashes = NSSwitch()
    let shortcutButton = NSButton(title: "", target: nil, action: nil)
    let fontLabel = NSTextField(labelWithString: "")
    let fontButton = SettingsContentView.actionButton(
        title: "Change…",
        symbol: "textformat.size",
        identifier: "change-font"
    )
    let backupSummary = NSTextField(labelWithString: "Backups: …")
    let checkUpdatesButton = SettingsContentView.actionButton(
        title: "Check for Updates",
        symbol: "arrow.clockwise",
        identifier: "check-for-updates"
    )
    let viewUpdateButton = SettingsContentView.actionButton(
        title: "View Release",
        symbol: "safari",
        identifier: "view-update"
    )
    let updateStatus = NSTextField(labelWithString: "Updates are checked only when requested.")
    let currentVersionLabel = NSTextField(labelWithString: "")

    var onNavigate: ((Page) -> Void)?
    var onOpenBackupFolder: (() -> Void)?

    private let pageHost = NSView()
    private var pages: [Page: NSView] = [:]
    private let updateProgress = NSProgressIndicator()

    override init(frame frameRect: NSRect) {
        navigation = NSSegmentedControl(
            labels: Page.allCases.map(\.title),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ page: Page) {
        navigation.selectedSegment = page.rawValue
        for (candidate, view) in pages {
            view.isHidden = candidate != page
        }
    }

    func setCheckingForUpdates(_ checking: Bool) {
        checkUpdatesButton.isEnabled = !checking
        checkUpdatesButton.title = checking ? "Checking…" : "Check for Updates"
        if checking {
            updateProgress.startAnimation(nil)
        } else {
            updateProgress.stopAnimation(nil)
        }
    }

    private func build() {
        material = .underWindowBackground
        state = .active

        navigation.identifier = NSUserInterfaceItemIdentifier("settings-navigation")
        navigation.segmentStyle = .rounded
        navigation.selectedSegment = Page.general.rawValue
        navigation.target = self
        navigation.action = #selector(navigationChanged)
        navigation.setAccessibilityLabel("Settings sections")
        navigation.translatesAutoresizingMaskIntoConstraints = false
        for page in Page.allCases {
            navigation.setImage(Self.symbol(page.symbol, label: page.title), forSegment: page.rawValue)
            navigation.setImageScaling(.scaleProportionallyDown, forSegment: page.rawValue)
            navigation.setWidth(128, forSegment: page.rawValue)
            navigation.setToolTip(page.title, forSegment: page.rawValue)
        }

        let header = NSVisualEffectView()
        header.material = .headerView
        header.blendingMode = .withinWindow
        header.state = .active
        header.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(navigation)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        pageHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        addSubview(separator)
        addSubview(pageHost)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 68),
            navigation.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            navigation.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            navigation.heightAnchor.constraint(equalToConstant: 34),
            separator.topAnchor.constraint(equalTo: header.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageHost.topAnchor.constraint(equalTo: separator.bottomAnchor),
            pageHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            pageHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageHost.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        pages = [
            .general: buildGeneralPage(),
            .editor: buildEditorPage(),
            .storage: buildStoragePage(),
            .updates: buildUpdatesPage(),
        ]
        for (page, view) in pages {
            view.identifier = NSUserInterfaceItemIdentifier("settings-page-\(page.identifier)")
            view.translatesAutoresizingMaskIntoConstraints = false
            pageHost.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: pageHost.topAnchor),
                view.centerXAnchor.constraint(equalTo: pageHost.centerXAnchor),
                view.widthAnchor.constraint(equalTo: pageHost.widthAnchor),
                view.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor),
            ])
        }
        show(.general)
    }

    private func buildGeneralPage() -> NSView {
        launchAtLogin.identifier = NSUserInterfaceItemIdentifier("launch-at-login")
        launchAtLogin.setAccessibilityLabel("Launch at login")

        shortcutButton.identifier = NSUserInterfaceItemIdentifier("global-shortcut")
        shortcutButton.bezelStyle = .rounded
        shortcutButton.setAccessibilityLabel("Global shortcut")
        shortcutButton.setContentHuggingPriority(.required, for: .horizontal)

        return page(
            title: "General",
            sections: [
                section(title: "STARTUP", rows: [
                    settingRow(title: "Launch at Login", control: launchAtLogin),
                ]),
                section(title: "KEYBOARD", rows: [
                    settingRow(title: "Global Shortcut", control: shortcutButton),
                ]),
            ]
        )
    }

    private func buildEditorPage() -> NSView {
        configureSwitch(spellChecking, identifier: SettingsKeys.spellChecking, label: "Check spelling")
        configureSwitch(smartQuotes, identifier: SettingsKeys.smartQuotes, label: "Smart quotes")
        configureSwitch(smartDashes, identifier: SettingsKeys.smartDashes, label: "Smart dashes")

        fontLabel.textColor = .secondaryLabelColor
        fontLabel.alignment = .right
        fontLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let fontControls = NSStackView(views: [fontLabel, fontButton])
        fontControls.orientation = .horizontal
        fontControls.alignment = .centerY
        fontControls.spacing = 10

        return page(
            title: "Editor",
            sections: [
                section(title: "TYPOGRAPHY", rows: [
                    settingRow(title: "Font", control: fontControls),
                ]),
                section(title: "WRITING", rows: [
                    settingRow(title: "Check Spelling", control: spellChecking),
                    settingRow(title: "Smart Quotes", control: smartQuotes),
                    settingRow(title: "Smart Dashes", control: smartDashes),
                ]),
            ]
        )
    }

    private func buildStoragePage() -> NSView {
        backupSummary.identifier = NSUserInterfaceItemIdentifier("backup-summary")
        backupSummary.textColor = .secondaryLabelColor
        backupSummary.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        backupSummary.maximumNumberOfLines = 2
        backupSummary.lineBreakMode = .byWordWrapping

        let openButton = Self.actionButton(
            title: "Open Backup Folder",
            symbol: "folder",
            identifier: "open-backup-folder"
        )
        openButton.target = self
        openButton.action = #selector(openBackupFolderPressed)

        return page(
            title: "Storage",
            sections: [
                section(title: "BACKUPS", rows: [
                    leadingBlock(backupSummary),
                    settingRow(title: "Backup Location", control: openButton),
                ]),
            ]
        )
    }

    private func buildUpdatesPage() -> NSView {
        currentVersionLabel.identifier = NSUserInterfaceItemIdentifier("current-version")
        currentVersionLabel.font = .systemFont(ofSize: 15, weight: .medium)

        updateStatus.identifier = NSUserInterfaceItemIdentifier("update-status")
        updateStatus.textColor = .secondaryLabelColor
        updateStatus.maximumNumberOfLines = 2
        updateStatus.lineBreakMode = .byWordWrapping
        updateStatus.setAccessibilityLabel("Update status")

        updateProgress.style = .spinning
        updateProgress.controlSize = .small
        updateProgress.isDisplayedWhenStopped = false

        viewUpdateButton.isHidden = true
        let actionRow = NSStackView(views: [
            checkUpdatesButton,
            viewUpdateButton,
            updateProgress,
        ])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 10

        let icon = NSImageView(image: Self.symbol(
            "square.and.pencil",
            label: "BetterTot"
        ))
        icon.contentTintColor = .controlAccentColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 54),
            icon.heightAnchor.constraint(equalToConstant: 54),
        ])

        let versionStack = NSStackView(views: [
            Self.textLabel("BetterTot", size: 22, weight: .semibold),
            currentVersionLabel,
        ])
        versionStack.orientation = .vertical
        versionStack.alignment = .leading
        versionStack.spacing = 3

        let productRow = NSStackView(views: [icon, versionStack])
        productRow.orientation = .horizontal
        productRow.alignment = .centerY
        productRow.spacing = 16

        let content = NSStackView(views: [productRow, updateStatus, actionRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 18
        return page(
            title: "Updates",
            sections: [
                section(title: "VERSION", rows: [leadingBlock(content)]),
            ]
        )
    }

    private func leadingBlock(_ content: NSView) -> NSView {
        let wrapper = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 12),
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            content.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -12),
        ])
        return wrapper
    }

    private func page(title: String, sections: [NSView]) -> NSView {
        let titleLabel = Self.textLabel(title, size: 24, weight: .semibold)
        let stack = NSStackView(views: [titleLabel] + sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 26
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.setCustomSpacing(30, after: titleLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for section in sections {
            section.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -68),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -30),
        ])
        return container
    }

    private func section(title: String, rows: [NSView]) -> NSView {
        let heading = Self.textLabel(title, size: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor

        var arranged: [NSView] = []
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let separator = NSBox()
                separator.boxType = .separator
                arranged.append(separator)
            }
            arranged.append(row)
        }
        let rowsStack = NSStackView(views: arranged)
        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.distribution = .fill
        rowsStack.spacing = 0
        rowsStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [heading, rowsStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 8
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        rowsStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func settingRow(title: String, control: NSView) -> NSView {
        let titleLabel = Self.textLabel(title, size: 14, weight: .regular)
        let spacer = Self.flexibleSpacer()
        let row = NSStackView(views: [titleLabel, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 14
        row.edgeInsets = NSEdgeInsets(top: 11, left: 0, bottom: 11, right: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return row
    }

    private func configureSwitch(_ control: NSSwitch, identifier: String, label: String) {
        control.identifier = NSUserInterfaceItemIdentifier(identifier)
        control.setAccessibilityLabel(label)
    }

    private static func actionButton(
        title: String,
        symbol: String,
        identifier: String
    ) -> NSButton {
        let button = NSButton(title: title, target: nil, action: nil)
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.bezelStyle = .rounded
        button.image = Self.symbol(symbol, label: title)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.setAccessibilityLabel(title)
        return button
    }

    private static func textLabel(
        _ text: String,
        size: CGFloat,
        weight: NSFont.Weight
    ) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        return label
    }

    private static func symbol(_ name: String, label: String) -> NSImage {
        NSImage(
            systemSymbolName: name,
            accessibilityDescription: label
        ) ?? NSImage()
    }

    private static func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    @objc private func navigationChanged() {
        guard let page = Page(rawValue: navigation.selectedSegment) else { return }
        show(page)
        onNavigate?(page)
    }

    @objc private func openBackupFolderPressed() {
        onOpenBackupFolder?()
    }
}
