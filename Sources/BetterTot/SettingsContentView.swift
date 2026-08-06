import AppKit

final class SettingsContentView: NSVisualEffectView {
    static var pageAccentColor: NSColor { .controlAccentColor }

    enum Page: Int, CaseIterable {
        case general
        case pads
        case editor
        case storage
        case updates

        var title: String {
            switch self {
            case .general: "General"
            case .pads: "Pads"
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
            case .pads: "circle.grid.2x2"
            case .editor: "pencil"
            case .storage: "internaldrive"
            case .updates: "arrow.clockwise"
            }
        }
    }

    let launchAtLogin = NSSwitch()
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
    let backupSummary = NSTextField(labelWithString: "Loading backup history...")
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
    let backupMirrorSwitch = NSSwitch()
    let backupMirrorButton = SettingsContentView.actionButton(
        title: "Choose Folder...",
        symbol: "folder.badge.plus",
        identifier: "choose-backup-mirror"
    )
    let backupMirrorStatus = NSTextField(
        labelWithString: "Choose a folder in iCloud Drive to keep a second copy."
    )
    let updateStatus = NSTextField(labelWithString: "Updates are checked only when requested.")
    let currentVersionLabel = NSTextField(labelWithString: "")
    let padCustomizationView = PadCustomizationView()

    var onNavigate: ((Page) -> Void)?
    var onOpenBackupFolder: (() -> Void)?

    private let pageHost = NSView()
    private let updateProgress = NSProgressIndicator()
    private let hourlyBackupCount = SettingsContentView.metricCountLabel(
        identifier: "backup-hourly-count",
        accessibilityLabel: "Hourly backups"
    )
    private let dailyBackupCount = SettingsContentView.metricCountLabel(
        identifier: "backup-daily-count",
        accessibilityLabel: "Daily backups"
    )
    private let manualBackupCount = SettingsContentView.metricCountLabel(
        identifier: "backup-manual-count",
        accessibilityLabel: "Manual backups"
    )
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

    func setBackupCounts(_ counts: [BackupKind: Int]) {
        let hourly = counts[.hourly] ?? 0
        let daily = counts[.daily] ?? 0
        let manual = counts[.manual] ?? 0
        let total = hourly + daily + manual

        hourlyBackupCount.stringValue = String(hourly)
        dailyBackupCount.stringValue = String(daily)
        manualBackupCount.stringValue = String(manual)
        backupSummary.stringValue = switch total {
        case 0: "No backups yet"
        case 1: "1 backup available"
        default: "\(total) backups available"
        }
        backupSummary.setAccessibilityValue(
            "\(backupSummary.stringValue). Hourly \(hourly), daily \(daily), manual \(manual)."
        )
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

    func setBackupMirror(
        enabled: Bool,
        selectedDirectory: URL?,
        status: BackupMirrorStatus?,
        busy: Bool = false
    ) {
        backupMirrorSwitch.state = enabled ? .on : .off
        backupMirrorSwitch.isEnabled = !busy
        backupMirrorButton.isEnabled = !busy
        backupMirrorButton.title = selectedDirectory == nil ? "Choose Folder..." : "Change..."

        let message: String
        if busy {
            message = "Copying existing backups to iCloud Drive..."
        } else if let error = status?.errorDescription {
            message = "Mirror unavailable: \(error)"
        } else if enabled, let directory = status?.directory {
            message = "Mirroring to \(directory.path(percentEncoded: false))."
        } else if selectedDirectory != nil {
            message = "Off. Local recovery remains active."
        } else {
            message = "Choose a folder in iCloud Drive to keep a second copy."
        }
        backupMirrorStatus.stringValue = message
        backupMirrorStatus.setAccessibilityValue(message)
    }

    private func build() {
        material = .underWindowBackground
        state = .active

        let sidebar = buildSidebar()

        sidebar.translatesAutoresizingMaskIntoConstraints = false
        pageHost.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sidebar)
        addSubview(pageHost)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
            sidebar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            sidebar.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -10),
            sidebar.widthAnchor.constraint(equalToConstant: 176),
            pageHost.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            pageHost.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 8),
            pageHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            pageHost.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
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
                ]),
                section(title: "Keyboard", rows: [
                    settingRow(
                        title: "Global Shortcut",
                        detail: "Show or hide the scratchpad.",
                        symbol: "keyboard",
                        tint: .systemBlue,
                        control: shortcutButton
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
        let fontControls = NSStackView(views: [fontLabel, fontButton])
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
        backupSummary.identifier = NSUserInterfaceItemIdentifier("backup-total")
        backupSummary.font = .systemFont(ofSize: 15, weight: .medium)
        backupSummary.maximumNumberOfLines = 1

        let summaryIcon = Self.iconWell(
            symbol: "externaldrive.badge.timemachine",
            label: "Backups",
            tint: .systemYellow,
            size: 34
        )
        let summaryRow = NSStackView(views: [summaryIcon, backupSummary])
        summaryRow.orientation = .horizontal
        summaryRow.alignment = .centerY
        summaryRow.spacing = 12

        let hourly = backupMetric(
            title: "Hourly",
            detail: "Keeps 24",
            symbol: "clock",
            tint: .systemBlue,
            count: hourlyBackupCount
        )
        let daily = backupMetric(
            title: "Daily",
            detail: "Keeps 14",
            symbol: "calendar",
            tint: .systemPurple,
            count: dailyBackupCount
        )
        let manual = backupMetric(
            title: "Manual",
            detail: "Kept until removed",
            symbol: "archivebox",
            tint: .systemOrange,
            count: manualBackupCount
        )
        let metrics = NSStackView(views: [
            hourly,
            verticalSeparator(),
            daily,
            verticalSeparator(),
            manual,
        ])
        metrics.orientation = .horizontal
        metrics.alignment = .centerY
        metrics.spacing = 14
        NSLayoutConstraint.activate([
            hourly.widthAnchor.constraint(equalTo: daily.widthAnchor),
            daily.widthAnchor.constraint(equalTo: manual.widthAnchor),
        ])

        let overview = NSStackView(views: [summaryRow, metrics])
        overview.orientation = .vertical
        overview.alignment = .width
        overview.spacing = 18

        let openButton = Self.actionButton(
            title: "Open Folder",
            symbol: "folder",
            identifier: "open-backup-folder"
        )
        openButton.target = self
        openButton.action = #selector(openBackupFolderPressed)

        backupMirrorSwitch.identifier = NSUserInterfaceItemIdentifier("backup-mirror-enabled")
        backupMirrorSwitch.setAccessibilityLabel("Mirror backups to iCloud Drive")
        backupMirrorStatus.identifier = NSUserInterfaceItemIdentifier("backup-mirror-status")
        backupMirrorStatus.textColor = .secondaryLabelColor
        backupMirrorStatus.maximumNumberOfLines = 2
        backupMirrorStatus.lineBreakMode = .byTruncatingMiddle
        let mirrorControls = NSStackView(views: [backupMirrorButton, backupMirrorSwitch])
        mirrorControls.orientation = .horizontal
        mirrorControls.alignment = .centerY
        mirrorControls.spacing = 10

        return page(
            .storage,
            sections: [
                section(title: "Local Recovery", rows: [leadingBlock(overview, fillWidth: true)]),
                section(title: "iCloud Drive", rows: [
                    settingRow(
                        title: "Backup Mirror",
                        detailView: backupMirrorStatus,
                        symbol: "icloud",
                        tint: .systemBlue,
                        control: mirrorControls
                    ),
                ]),
                section(title: "Local Storage", rows: [
                    settingRow(
                        title: "Backup Folder",
                        detail: "Hourly, daily, and manual snapshots.",
                        symbol: "folder",
                        tint: .systemTeal,
                        control: openButton
                    ),
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
        let actionRow = NSStackView(views: [
            checkUpdatesButton,
            viewUpdateButton,
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
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -32),
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

    private func backupMetric(
        title: String,
        detail: String,
        symbol: String,
        tint: NSColor,
        count: NSTextField
    ) -> NSView {
        let icon = NSImageView(image: Self.symbol(symbol, label: title))
        icon.contentTintColor = tint
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)

        let titleLabel = Self.textLabel(title, size: 13, weight: .medium)
        let detailLabel = Self.detailLabel(detail)
        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1

        let text = NSStackView(views: [count, labels])
        text.orientation = .horizontal
        text.alignment = .centerY
        text.spacing = 9

        let metric = NSStackView(views: [icon, text])
        metric.orientation = .horizontal
        metric.alignment = .centerY
        metric.spacing = 8
        return metric
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

    private func verticalSeparator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 42).isActive = true
        return separator
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
        #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                button.bezelStyle = .glass
                return
            }
        #endif
        button.bezelStyle = .rounded
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

    private static func metricCountLabel(
        identifier: String,
        accessibilityLabel: String
    ) -> NSTextField {
        let label = textLabel("0", size: 23, weight: .semibold)
        label.identifier = NSUserInterfaceItemIdentifier(identifier)
        label.alignment = .right
        label.setAccessibilityLabel(accessibilityLabel)
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 24).isActive = true
        return label
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

    @objc private func openBackupFolderPressed() {
        onOpenBackupFolder?()
    }
}
