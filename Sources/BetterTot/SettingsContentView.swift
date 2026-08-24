import AppKit

final class SettingsContentView: NSVisualEffectView {
    static var pageAccentColor: NSColor { .controlAccentColor }
    typealias Page = SettingsPage
    let launchAtLogin = NSSwitch()
    let showStatistics = NSSwitch()
    let spellChecking = NSSwitch()
    let smartQuotes = NSSwitch()
    let smartDashes = NSSwitch()
    let writingTools = NSSwitch()
    let shortcutButton = NSButton(title: "", target: nil, action: nil)
    let fontLabel = NSTextField(labelWithString: "")
    let fontButton = SettingsContentView.actionButton(
        title: "Change...",
        symbol: "textformat.size",
        identifier: "change-font"
    )
    let backupStatus = NSTextField(labelWithString: "Checking iCloud backup...")
    let latestBackupDate = NSTextField(labelWithString: "Never")
    let latestBackupSize = NSTextField(labelWithString: "—")
    let backupNowButton = SettingsContentView.actionButton(
        title: "Back Up Now",
        symbol: "arrow.clockwise.icloud",
        identifier: "backup-now"
    )
    let restoreBackupButton = SettingsContentView.actionButton(
        title: "Restore...",
        symbol: "clock.arrow.circlepath",
        identifier: "restore-backup"
    )
    let openICloudBackupsButton = SettingsContentView.actionButton(
        title: "Open in iCloud Drive",
        symbol: "folder",
        identifier: "open-icloud-backups"
    )
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
    let updateStatus = NSTextField(
        labelWithString: "Updates are checked automatically. You can also check now."
    )
    let currentVersionLabel = NSTextField(labelWithString: "")
    let padCustomizationView = PadCustomizationView()

    var onNavigate: ((Page) -> Void)?
    var onBackUpNow: (() -> Void)?
    var onRestoreBackup: (() -> Void)?
    var onOpenICloudBackups: (() -> Void)?

    private let pageHost = NSView()
    private let pageContainer: NSView = {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                let container = NSGlassEffectContainerView()
                container.spacing = 8
                return container
            }
        #endif
        return NSView()
    }()
    private let updateProgress = NSProgressIndicator()
    private var navigationButtons: [Page: SettingsSidebarButton] = [:]
    private var pages: [Page: NSView] = [:]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ page: Page) {
        for (candidate, button) in navigationButtons {
            button.state = candidate == page ? .on : .off
        }
        for (candidate, view) in pages {
            view.isHidden = candidate != page
        }
    }

    func setBackupSummary(_ summary: BackupRepositorySummary, busy: Bool = false) {
        latestBackupDate.stringValue = summary.latestBackupDate.map {
            BackupDisplayFormatting.date($0)
        } ?? "Never"
        latestBackupSize.stringValue = summary.latestBackupSizeBytes.map {
            BackupDisplayFormatting.size($0)
        } ?? "—"

        let ready: Bool
        switch summary.health {
        case .ready:
            ready = true
            backupStatus.stringValue = summary.totalCount == 0
                ? "Ready to back up to iCloud Drive."
                : "Your latest backup is stored in iCloud Drive."
        case .unavailable(let reason):
            ready = false
            backupStatus.stringValue = reason
        case .blocked(let reason):
            ready = false
            backupStatus.stringValue = "Backup needs attention. \(reason)"
        }
        backupNowButton.isEnabled = ready && !busy
        restoreBackupButton.isEnabled = summary.totalCount > 0 && !busy
        openICloudBackupsButton.isEnabled = summary.canOpenDirectory && !busy
        backupNowButton.title = busy ? "Backing Up..." : "Back Up Now"
        backupStatus.setAccessibilityValue(backupStatus.stringValue)
    }

    func setCheckingForUpdates(_ checking: Bool) {
        checkUpdatesButton.isEnabled = !checking
        checkUpdatesButton.title = checking ? "Checking..." : "Check for Updates"
        if checking {
            updateProgress.startAnimation(nil)
        } else {
            updateProgress.stopAnimation(nil)
        }
    }

    func setViewUpdateButtonVisible(_ visible: Bool) {
        viewUpdateButton.isHidden = !visible
        #if compiler(>=6.2)
            if #available(macOS 26.0, *),
               let host = viewUpdateButton.superview as? BetterTotGlassEffectView {
                host.isHidden = !visible
            }
        #endif
    }

    private func build() {
        material = .underWindowBackground
        state = .active

        let sidebar = buildSidebar()

        sidebar.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.translatesAutoresizingMaskIntoConstraints = false
        pageHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sidebar)
        addSubview(pageContainer)
        #if compiler(>=6.2)
            if #available(macOS 26.0, *),
               let glassContainer = pageContainer as? NSGlassEffectContainerView {
                glassContainer.contentView = pageHost
            } else {
                pageContainer.addSubview(pageHost)
            }
        #else
            pageContainer.addSubview(pageHost)
        #endif

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            sidebar.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -10),
            sidebar.widthAnchor.constraint(equalToConstant: 140),
            pageContainer.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            pageContainer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 8),
            pageContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageContainer.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            pageHost.topAnchor.constraint(equalTo: pageContainer.topAnchor),
            pageHost.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
            pageHost.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
            pageHost.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor),
        ])

        pages = [
            .general: buildGeneralPage(),
            .pads: buildPadsPage(),
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
                view.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor),
            ])
        }
        show(.general)
    }

    private func buildSidebar() -> NSView {
        let content = NSView()

        let appIcon = NSImageView(image: BetterTotAppIcon.make())
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            appIcon.widthAnchor.constraint(equalToConstant: 34),
            appIcon.heightAnchor.constraint(equalToConstant: 34),
        ])

        let appTitle = Self.textLabel("BetterTot", size: 15, weight: .semibold)
        let settingsTitle = Self.textLabel("Settings", size: 11, weight: .regular)
        settingsTitle.textColor = .secondaryLabelColor
        let titleStack = NSStackView(views: [appTitle, settingsTitle])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 1

        let brand = NSStackView(views: [appIcon, titleStack])
        brand.orientation = .horizontal
        brand.alignment = .centerY
        brand.spacing = 10

        let navButtons = Page.allCases.map { page in
            let button = SettingsSidebarButton(
                title: page.title,
                symbol: page.symbol,
                page: page
            )
            button.target = self
            button.action = #selector(navigationPressed(_:))
            navigationButtons[page] = button
            return button
        }
        let navigation = NSStackView(views: navButtons)
        navigation.identifier = NSUserInterfaceItemIdentifier("settings-navigation")
        navigation.orientation = .vertical
        navigation.alignment = .leading
        navigation.spacing = 3
        navigation.setAccessibilityElement(true)
        navigation.setAccessibilityRole(.radioGroup)
        navigation.setAccessibilityLabel("Settings sections")
        for button in navButtons {
            button.widthAnchor.constraint(equalTo: navigation.widthAnchor).isActive = true
        }

        let spacer = Self.flexibleSpacer()
        let stack = NSStackView(views: [brand, navigation, spacer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            brand.widthAnchor.constraint(equalTo: stack.widthAnchor),
            navigation.widthAnchor.constraint(equalTo: stack.widthAnchor),
            spacer.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                return BetterTotGlassEffectView(content: content, cornerRadius: 16)
            }
        #endif

        let material = NSVisualEffectView()
        material.material = .sidebar
        material.blendingMode = .withinWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 16
        material.layer?.masksToBounds = true
        content.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: material.topAnchor),
            content.leadingAnchor.constraint(equalTo: material.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: material.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: material.bottomAnchor),
        ])
        return material
    }

    private func buildGeneralPage() -> NSView {
        launchAtLogin.identifier = NSUserInterfaceItemIdentifier("launch-at-login")
        launchAtLogin.setAccessibilityLabel("Launch at login")
        configureSwitch(
            showStatistics,
            identifier: SettingsKeys.showStatistics,
            label: "Show text statistics"
        )

        shortcutButton.identifier = NSUserInterfaceItemIdentifier("global-shortcut")
        Self.applyCommandButtonStyle(to: shortcutButton)
        shortcutButton.setAccessibilityLabel("Global shortcut")
        shortcutButton.setContentHuggingPriority(.required, for: .horizontal)

        return page(
            .general,
            sections: [
                section(title: "Application", rows: [
                    settingRow(
                        title: "Launch at Login",
                        detail: "Open BetterTot when you sign in.",
                        symbol: "power",
                        tint: .systemGreen,
                        control: launchAtLogin
                    ),
                    settingRow(
                        title: "Text Statistics",
                        detail: "Show line, word, and character counts in the footer.",
                        symbol: "number",
                        tint: .systemTeal,
                        control: showStatistics
                    ),
                ]),
                section(title: "Keyboard", rows: [
                    settingRow(
                        title: "Global Shortcut",
                        detail: "Show or hide the scratchpad.",
                        symbol: "keyboard",
                        tint: .systemBlue,
                        control: Self.glassButtonHost(shortcutButton)
                    ),
                ]),
            ]
        )
    }

    private func buildEditorPage() -> NSView {
        configureSwitch(spellChecking, identifier: SettingsKeys.spellChecking, label: "Check spelling")
        configureSwitch(smartQuotes, identifier: SettingsKeys.smartQuotes, label: "Smart quotes")
        configureSwitch(smartDashes, identifier: SettingsKeys.smartDashes, label: "Smart dashes")
        configureSwitch(
            writingTools,
            identifier: SettingsKeys.writingTools,
            label: "Writing Tools and Siri"
        )

        fontLabel.textColor = .secondaryLabelColor
        fontLabel.alignment = .right
        fontLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let fontControls = NSStackView(views: [fontLabel, Self.glassButtonHost(fontButton)])
        fontControls.orientation = .horizontal
        fontControls.alignment = .centerY
        fontControls.spacing = 10

        return page(
            .editor,
            sections: [
                section(title: "Typography", rows: [
                    settingRow(
                        title: "Editor Font",
                        detail: "Applied consistently across every pad.",
                        symbol: "textformat.size",
                        tint: .systemPurple,
                        control: fontControls
                    ),
                ]),
                section(title: "Writing", rows: [
                    settingRow(
                        title: "Check Spelling",
                        detail: "Mark possible misspellings as you type.",
                        symbol: "checkmark.circle",
                        tint: .systemGreen,
                        control: spellChecking
                    ),
                    settingRow(
                        title: "Smart Quotes",
                        detail: "Use typographic quotation marks.",
                        symbol: "quote.opening",
                        tint: .systemOrange,
                        control: smartQuotes
                    ),
                    settingRow(
                        title: "Smart Dashes",
                        detail: "Use typographic dashes while writing.",
                        symbol: "minus",
                        tint: .systemPink,
                        control: smartDashes
                    ),
                    settingRow(
                        title: "Writing Tools & Siri",
                        detail: "Use Apple Intelligence writing assistance on supported Macs.",
                        symbol: "wand.and.stars",
                        tint: .systemBlue,
                        control: writingTools
                    ),
                ]),
            ]
        )
    }

    private func buildPadsPage() -> NSView {
        page(
            .pads,
            sections: [
                section(title: "Scratchpads", rows: [
                    leadingBlock(padCustomizationView, fillWidth: true),
                ]),
            ]
        )
    }

    private func buildStoragePage() -> NSView {
        backupStatus.identifier = NSUserInterfaceItemIdentifier("backup-status")
        backupStatus.textColor = .secondaryLabelColor
        backupStatus.font = .systemFont(ofSize: 11, weight: .regular)
        backupStatus.maximumNumberOfLines = 2
        backupStatus.lineBreakMode = .byWordWrapping
        latestBackupDate.identifier = NSUserInterfaceItemIdentifier("backup-latest-date")
        latestBackupSize.identifier = NSUserInterfaceItemIdentifier("backup-latest-size")
        latestBackupDate.font = .systemFont(ofSize: 11, weight: .medium)
        latestBackupSize.font = .systemFont(ofSize: 11, weight: .medium)
        let latest = NSStackView(views: [Self.detailLabel("Latest Backup"), latestBackupDate])
        latest.orientation = .horizontal
        latest.alignment = .firstBaseline
        latest.spacing = 4
        let size = NSStackView(views: [Self.detailLabel("Size"), latestBackupSize])
        size.orientation = .horizontal
        size.alignment = .firstBaseline
        size.spacing = 4
        let metadata = NSStackView(views: [latest, size])
        metadata.orientation = .horizontal
        metadata.alignment = .firstBaseline
        metadata.spacing = 16
        let statusDetails = NSStackView(views: [backupStatus, metadata])
        statusDetails.orientation = .vertical
        statusDetails.alignment = .leading
        statusDetails.spacing = 2

        backupNowButton.target = self
        backupNowButton.action = #selector(backUpNowPressed)
        restoreBackupButton.target = self
        restoreBackupButton.action = #selector(restoreBackupPressed)
        openICloudBackupsButton.target = self
        openICloudBackupsButton.action = #selector(openICloudBackupsPressed)
        let actions = NSStackView(views: [
            Self.glassButtonHost(backupNowButton),
            Self.glassButtonHost(restoreBackupButton),
            Self.glassButtonHost(openICloudBackupsButton),
        ])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        return page(
            .storage,
            sections: [
                section(title: "iCloud Backup", rows: [
                    settingRow(
                        title: "Backup Status",
                        detailView: statusDetails,
                        symbol: "icloud",
                        tint: .systemBlue,
                        control: NSView()
                    ),
                    leadingBlock(actions),
                ]),
            ]
        )
    }

    private func buildUpdatesPage() -> NSView {
        currentVersionLabel.identifier = NSUserInterfaceItemIdentifier("current-version")
        currentVersionLabel.font = .systemFont(ofSize: 13, weight: .regular)
        currentVersionLabel.textColor = .secondaryLabelColor

        updateStatus.identifier = NSUserInterfaceItemIdentifier("update-status")
        updateStatus.textColor = .secondaryLabelColor
        updateStatus.maximumNumberOfLines = 2
        updateStatus.lineBreakMode = .byWordWrapping
        updateStatus.setAccessibilityLabel("Update status")

        updateProgress.style = .spinning
        updateProgress.controlSize = .small
        updateProgress.isDisplayedWhenStopped = false

        checkUpdatesButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 146).isActive = true
        viewUpdateButton.isHidden = true
        let viewUpdateControl = Self.glassButtonHost(viewUpdateButton)
        viewUpdateControl.isHidden = true
        let actionRow = NSStackView(views: [
            Self.glassButtonHost(checkUpdatesButton),
            viewUpdateControl,
            updateProgress,
        ])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY
        actionRow.spacing = 10

        let icon = NSImageView(image: BetterTotAppIcon.make())
        icon.identifier = NSUserInterfaceItemIdentifier("bettertot-app-icon")
        icon.setAccessibilityLabel("BetterTot app icon")
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 62),
            icon.heightAnchor.constraint(equalToConstant: 62),
        ])

        let versionStack = NSStackView(views: [
            Self.textLabel("BetterTot", size: 20, weight: .semibold),
            currentVersionLabel,
        ])
        versionStack.orientation = .vertical
        versionStack.alignment = .leading
        versionStack.spacing = 3

        let productRow = NSStackView(views: [icon, versionStack])
        productRow.orientation = .horizontal
        productRow.alignment = .centerY
        productRow.spacing = 16

        return page(
            .updates,
            sections: [
                section(title: "Version", rows: [leadingBlock(productRow)]),
                section(title: "Software Update", rows: [
                    settingRow(
                        title: "Update Status",
                        detailView: updateStatus,
                        symbol: "arrow.triangle.2.circlepath",
                        tint: .systemBlue,
                        control: actionRow
                    ),
                ]),
            ]
        )
    }

    private func page(_ page: Page, sections: [NSView]) -> NSView {
        let headerIcon = Self.pageHeaderIcon(for: page)
        let title = Self.textLabel(page.title, size: 22, weight: .semibold)
        let header = NSStackView(views: [headerIcon, title])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10

        let stack = NSStackView(views: [header] + sections)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        stack.setCustomSpacing(24, after: header)
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        stack.translatesAutoresizingMaskIntoConstraints = false
        for section in sections {
            section.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            section.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -24),
        ])
        return container
    }

    private func section(title: String, rows: [NSView]) -> NSView {
        let heading = Self.textLabel(title, size: 12, weight: .semibold)
        heading.textColor = .secondaryLabelColor

        var arranged: [NSView] = []
        for (index, row) in rows.enumerated() {
            if index > 0 {
                arranged.append(horizontalSeparator())
            }
            arranged.append(row)
        }
        let rowsStack = NSStackView(views: arranged)
        rowsStack.orientation = .vertical
        rowsStack.alignment = .width
        rowsStack.spacing = 0

        let stack = NSStackView(views: [heading, rowsStack])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        rowsStack.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return stack
    }

    private func settingRow(
        title: String,
        detail: String,
        symbol: String,
        tint: NSColor,
        control: NSView
    ) -> NSView {
        settingRow(
            title: title,
            detailView: Self.detailLabel(detail),
            symbol: symbol,
            tint: tint,
            control: control
        )
    }

    private func settingRow(
        title: String,
        detailView: NSView,
        symbol: String,
        tint: NSColor,
        control: NSView
    ) -> NSView {
        let icon = Self.iconWell(symbol: symbol, label: title, tint: tint, size: 30)
        let titleLabel = Self.textLabel(title, size: 14, weight: .medium)
        detailView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let labelStack = NSStackView(views: [titleLabel, detailView])
        labelStack.orientation = .vertical
        labelStack.alignment = .leading
        labelStack.spacing = 2
        labelStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [icon, labelStack, Self.flexibleSpacer(), control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 9, left: 0, bottom: 9, right: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 56).isActive = true
        return row
    }

    private func leadingBlock(_ content: NSView, fillWidth: Bool = false) -> NSView {
        let wrapper = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(content)
        var constraints = [
            content.topAnchor.constraint(equalTo: wrapper.topAnchor, constant: 10),
            content.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            content.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor, constant: -10),
            content.trailingAnchor.constraint(lessThanOrEqualTo: wrapper.trailingAnchor),
        ]
        if fillWidth {
            constraints.append(content.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor))
        }
        NSLayoutConstraint.activate(constraints)
        return wrapper
    }

    private func horizontalSeparator() -> NSView {
        let wrapper = NSView()
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        wrapper.addSubview(separator)
        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: wrapper.topAnchor),
            separator.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 42),
            separator.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: wrapper.bottomAnchor),
        ])
        return wrapper
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
        applyCommandButtonStyle(to: button)
        button.image = symbolImage(symbol, label: title, pointSize: 13)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.setAccessibilityLabel(title)
        return button
    }

    private static func applyCommandButtonStyle(to button: NSButton) {
        button.contentTintColor = .labelColor
        button.isBordered = true
        button.showsBorderOnlyWhileMouseInside = false
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                button.bezelStyle = .glass
            } else {
                button.bezelStyle = .rounded
            }
        #else
            button.bezelStyle = .rounded
        #endif
        button.controlSize = .regular
    }

    private static func glassButtonHost(_ button: NSButton) -> NSView {
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                let host = BetterTotGlassEffectView(content: button, cornerRadius: 8)
                let buttonSize = button.intrinsicContentSize
                NSLayoutConstraint.activate([
                    host.widthAnchor.constraint(
                        greaterThanOrEqualToConstant: buttonSize.width + 16
                    ),
                    host.heightAnchor.constraint(greaterThanOrEqualToConstant: 30),
                ])
                return host
            }
        #endif
        return button
    }

    private static func pageHeaderIcon(for page: Page) -> NSView {
        let container = NSView()
        container.identifier = NSUserInterfaceItemIdentifier(
            "settings-header-icon-\(page.identifier)"
        )
        container.wantsLayer = true
        container.layer?.cornerRadius = 16
        container.layer?.cornerCurve = .continuous
        container.layer?.backgroundColor = pageAccentColor.withAlphaComponent(0.82).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        container.setAccessibilityElement(false)

        let image = NSImageView(image: symbolImage(page.symbol, label: page.title, pointSize: 15))
        image.contentTintColor = .selectedControlTextColor
        image.translatesAutoresizingMaskIntoConstraints = false
        image.setAccessibilityElement(false)
        container.addSubview(image)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 32),
            container.heightAnchor.constraint(equalToConstant: 32),
            image.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 18),
            image.heightAnchor.constraint(equalToConstant: 18),
        ])
        return container
    }

    private static func iconWell(
        symbol: String,
        label: String,
        tint: NSColor,
        size: CGFloat
    ) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = 7
        container.layer?.backgroundColor = tint.withAlphaComponent(0.15).cgColor
        container.translatesAutoresizingMaskIntoConstraints = false

        let image = NSImageView(image: symbolImage(symbol, label: label, pointSize: 14))
        image.contentTintColor = tint
        image.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(image)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: size),
            container.heightAnchor.constraint(equalToConstant: size),
            image.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 17),
            image.heightAnchor.constraint(equalToConstant: 17),
        ])
        return container
    }

    private static func detailLabel(_ text: String) -> NSTextField {
        let label = textLabel(text, size: 11, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
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

    private static func symbolImage(
        _ name: String,
        label: String,
        pointSize: CGFloat
    ) -> NSImage {
        symbol(name, label: label).withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        ) ?? NSImage()
    }

    private static func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    @objc private func navigationPressed(_ sender: SettingsSidebarButton) {
        show(sender.page)
        window?.makeFirstResponder(sender)
        onNavigate?(sender.page)
    }

    @objc private func backUpNowPressed() { onBackUpNow?() }
    @objc private func restoreBackupPressed() { onRestoreBackup?() }
    @objc private func openICloudBackupsPressed() { onOpenICloudBackups?() }

}
