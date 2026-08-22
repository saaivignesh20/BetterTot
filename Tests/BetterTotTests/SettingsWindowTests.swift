import AppKit
import Carbon.HIToolbox
import XCTest
@testable import BetterTot

@MainActor
final class SettingsWindowTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var root: URL!

    override func setUpWithError() throws {
        suiteName = "BetterTot.SettingsWindowTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettertot-settings-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    func testRegisteredDefaultsMatchEditorBehavior() {
        defaults.register(defaults: SettingsKeys.defaults)

        XCTAssertTrue(defaults.bool(forKey: SettingsKeys.spellChecking))
        XCTAssertFalse(defaults.bool(forKey: SettingsKeys.smartQuotes))
        XCTAssertFalse(defaults.bool(forKey: SettingsKeys.smartDashes))
        XCTAssertFalse(defaults.bool(forKey: SettingsKeys.writingTools))
        XCTAssertEqual(defaults.string(forKey: SettingsKeys.fontName), "AmericanTypewriter")
        XCTAssertEqual(defaults.double(forKey: SettingsKeys.fontSize), 14)
        XCTAssertEqual(SettingsKeys.editorFont(in: defaults).fontName, "AmericanTypewriter")
    }

    func testLegacyBackupLocationAcceptsOnlyValidFileURLsForMigration() {
        defaults.register(defaults: SettingsKeys.defaults)
        let directory = root.appendingPathComponent("iCloud Drive", isDirectory: true)

        SettingsKeys.saveLegacyBackupDirectory(directory, to: defaults)
        XCTAssertEqual(SettingsKeys.storedLegacyBackupDirectory(in: defaults), directory)

        SettingsKeys.saveLegacyBackupDirectory(URL(string: "https://example.com")!, to: defaults)
        XCTAssertNil(SettingsKeys.storedLegacyBackupDirectory(in: defaults))
    }

    func testSettingsContentViewBuildsFiveSidebarPages() throws {
        let view = SettingsContentView()
        let subviews = allSubviews(of: view)

        XCTAssertEqual(
            subviews.filter {
                $0.identifier?.rawValue.hasPrefix("settings-page-") == true
            }.count,
            5
        )
        XCTAssertEqual(
            subviews.compactMap { $0 as? NSButton }.filter {
                $0.identifier?.rawValue.hasPrefix("settings-navigation-") == true
            }.count,
            5
        )
    }

    func testSettingsCommandButtonsUseCompatibleSystemStyle() throws {
        let view = SettingsContentView()
        let commandIdentifiers = [
            "global-shortcut",
            "change-font",
            "backup-now",
            "restore-backup",
            "open-icloud-backups",
            "recheck-icloud-backups",
            "check-for-updates",
            "view-update",
        ]
        let buttons = allSubviews(of: view).compactMap { $0 as? NSButton }

        for identifier in commandIdentifiers {
            let button = try XCTUnwrap(buttons.first {
                $0.identifier?.rawValue == identifier
            })
            XCTAssertEqual(button.contentTintColor, .labelColor, identifier)
            XCTAssertTrue(button.isBordered, identifier)
            XCTAssertEqual(button.bezelStyle, .rounded, identifier)
        }
    }

    func testStoragePageExposesOnlyICloudBackupControls() throws {
        let view = SettingsContentView()
        let subviews = allSubviews(of: view)
        let identifiers = Set(subviews.compactMap { $0.identifier?.rawValue })
        let text = subviews.compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: " ")

        XCTAssertTrue(identifiers.contains("backup-latest-date"))
        XCTAssertTrue(identifiers.contains("backup-latest-size"))
        XCTAssertTrue(identifiers.contains("backup-now"))
        XCTAssertTrue(identifiers.contains("restore-backup"))
        XCTAssertTrue(identifiers.contains("open-icloud-backups"))
        XCTAssertTrue(identifiers.contains("recheck-icloud-backups"))
        XCTAssertFalse(identifiers.contains("backup-mirror-enabled"))
        XCTAssertFalse(identifiers.contains("choose-backup-mirror"))
        XCTAssertFalse(identifiers.contains("open-backup-folder"))
        XCTAssertFalse(text.contains("Local Recovery"))
        XCTAssertFalse(text.contains("Backup Mirror"))
        XCTAssertFalse(text.contains("Local Storage"))
    }

    func testBlockedBackupRepositoryStillAllowsRestoreOfExistingSnapshots() {
        let view = SettingsContentView()
        view.setBackupSummary(BackupRepositorySummary(
            health: .blocked("Unexpected files need attention."),
            directory: root,
            canOpenDirectory: true,
            latestBackupDate: Date(),
            latestBackupSizeBytes: 42,
            counts: [.manual: 1]
        ))

        XCTAssertFalse(view.backupNowButton.isEnabled)
        XCTAssertTrue(view.restoreBackupButton.isEnabled)
    }

    func testSettingsPageHeadersUseCircularAccentIcons() {
        let windowSize = NSSize(width: 600, height: 460)
        let view = SettingsContentView(frame: NSRect(origin: .zero, size: windowSize))
        view.layoutSubtreeIfNeeded()
        let headerIcons = allSubviews(of: view).filter {
            $0.identifier?.rawValue.hasPrefix("settings-header-icon-") == true
        }

        XCTAssertEqual(headerIcons.count, SettingsContentView.Page.allCases.count)
        XCTAssertTrue(headerIcons.allSatisfy { $0.frame.size == NSSize(width: 32, height: 32) })
        XCTAssertTrue(headerIcons.allSatisfy { $0.layer?.cornerRadius == 16 })
        XCTAssertTrue(headerIcons.allSatisfy { $0.layer?.backgroundColor != nil })
    }

    func testSettingsWindowUsesUnifiedTransparentTitlebar() throws {
        let controller = SettingsWindowController(
            store: WorkspaceStore(root: root),
            shortcutService: ShortcutServiceStub(currentShortcut: .defaultShortcut),
            defaults: defaults
        )
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)

        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
    }

    func testSettingsWindowUsesCompactFixedWidth() throws {
        let controller = SettingsWindowController(
            store: WorkspaceStore(root: root),
            shortcutService: ShortcutServiceStub(currentShortcut: .defaultShortcut),
            defaults: defaults
        )
        defer { controller.close() }
        let window = try XCTUnwrap(controller.window)
        let view = try XCTUnwrap(window.contentView as? SettingsContentView)

        view.setBackupSummary(BackupRepositorySummary(
            health: .ready,
            directory: URL(fileURLWithPath: "/Users/example/Library/Mobile Documents/"
                + String(repeating: "BetterTot/", count: 20)),
            canOpenDirectory: true,
            latestBackupDate: nil,
            latestBackupSizeBytes: nil,
            counts: [:]
        ))

        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(window.contentView?.frame.size, NSSize(width: 600, height: 460))
        XCTAssertEqual(window.contentMinSize, NSSize(width: 600, height: 460))
        XCTAssertEqual(window.contentMaxSize, NSSize(width: 600, height: 460))
        XCTAssertFalse(window.styleMask.contains(.resizable))
    }

    func testSettingsPagesRenderAtWindowSize() throws {
        let windowSize = NSSize(width: 600, height: 460)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let view = SettingsContentView(frame: NSRect(origin: .zero, size: windowSize))
        window.contentView = view

        let snapshotDirectory = ProcessInfo.processInfo.environment[
            "BETTERTOT_SETTINGS_SNAPSHOT_DIR"
        ].map { URL(fileURLWithPath: $0, isDirectory: true) }
        if let snapshotDirectory {
            try FileManager.default.createDirectory(
                at: snapshotDirectory,
                withIntermediateDirectories: true
            )
        }

        let appearances: [(name: String, value: NSAppearance.Name)] = [
            ("light", .aqua),
            ("dark", .darkAqua),
            ("high-contrast-light", .accessibilityHighContrastAqua),
            ("high-contrast-dark", .accessibilityHighContrastDarkAqua),
        ]
        for appearance in appearances {
            view.appearance = NSAppearance(named: appearance.value)
            for page in SettingsContentView.Page.allCases {
                view.show(page)
                view.layoutSubtreeIfNeeded()
                window.displayIfNeeded()

                let representation = try XCTUnwrap(
                    view.bitmapImageRepForCachingDisplay(in: view.bounds)
                )
                view.cacheDisplay(in: view.bounds, to: representation)
                let png = try XCTUnwrap(
                    representation.representation(using: .png, properties: [:])
                )
                XCTAssertGreaterThan(
                    png.count,
                    10_000,
                    "\(page.title) rendered blank in \(appearance.name)"
                )

                if let snapshotDirectory {
                    try png.write(to: snapshotDirectory.appendingPathComponent(
                        "\(appearance.name)-\(page.identifier).png"
                    ))
                }
            }
        }
    }

    func testFontSaveAndLoadRoundTripWithFallbackForUnknownFont() throws {
        defaults.register(defaults: SettingsKeys.defaults)
        let font = try XCTUnwrap(NSFont(name: "Menlo", size: 18))

        SettingsKeys.save(font, to: defaults)

        let restored = SettingsKeys.editorFont(in: defaults)
        XCTAssertEqual(restored.fontName, font.fontName)
        XCTAssertEqual(restored.pointSize, 18)

        defaults.set("Definitely Not A Font", forKey: SettingsKeys.fontName)
        defaults.set(16.0, forKey: SettingsKeys.fontSize)
        let fallback = SettingsKeys.editorFont(in: defaults)
        XCTAssertEqual(fallback.fontName, NSFont.systemFont(ofSize: 16).fontName)
        XCTAssertEqual(fallback.pointSize, 16)
    }

    func testShortcutPersistenceRoundTripAndInvalidDataFallback() throws {
        let shortcut = Shortcut(
            keyCode: 3,
            carbonModifiers: UInt32(controlKey | optionKey),
            display: "⌃⌥F"
        )

        SettingsKeys.save(shortcut, to: defaults)
        XCTAssertEqual(SettingsKeys.loadShortcut(from: defaults), shortcut)

        let invalid = Shortcut(keyCode: 11, carbonModifiers: 0, display: "B")
        defaults.set(try JSONEncoder().encode(invalid), forKey: SettingsKeys.globalShortcut)
        XCTAssertEqual(SettingsKeys.loadShortcut(from: defaults), .defaultShortcut)

        defaults.set(Data("not-json".utf8), forKey: SettingsKeys.globalShortcut)
        XCTAssertEqual(SettingsKeys.loadShortcut(from: defaults), .defaultShortcut)
    }

    func testControllerRefreshesStateAndCheckboxActionsPersist() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        defaults.set(false, forKey: SettingsKeys.spellChecking)
        defaults.set(true, forKey: SettingsKeys.smartQuotes)
        defaults.set(true, forKey: SettingsKeys.smartDashes)
        SettingsKeys.save(try XCTUnwrap(NSFont(name: "Menlo", size: 17)), to: defaults)

        let shortcut = Shortcut(
            keyCode: 105,
            carbonModifiers: UInt32(optionKey | cmdKey),
            display: "⌥⌘F13"
        )
        let shortcutService = ShortcutServiceStub(currentShortcut: shortcut)
        let store = WorkspaceStore(root: root)
        _ = try await store.load()
        let controller = SettingsWindowController(
            store: store,
            shortcutService: shortcutService,
            defaults: defaults
        )
        controller.present()
        defer { controller.close() }

        let views = allSubviews(of: try XCTUnwrap(controller.window?.contentView))
        let buttons = views.compactMap { $0 as? NSButton }
        let switches = views.compactMap { $0 as? NSSwitch }
        let spell = try XCTUnwrap(switches.first {
            $0.identifier?.rawValue == SettingsKeys.spellChecking
        })
        let quotes = try XCTUnwrap(switches.first {
            $0.identifier?.rawValue == SettingsKeys.smartQuotes
        })
        let dashes = try XCTUnwrap(switches.first {
            $0.identifier?.rawValue == SettingsKeys.smartDashes
        })
        let writingTools = try XCTUnwrap(switches.first {
            $0.identifier?.rawValue == SettingsKeys.writingTools
        })
        XCTAssertEqual(spell.state, .off)
        XCTAssertEqual(quotes.state, .on)
        XCTAssertEqual(dashes.state, .on)
        XCTAssertEqual(writingTools.state, .off)
        XCTAssertEqual(buttons.first { $0.accessibilityLabel() == "Global shortcut" }?.title, "⌥⌘F13")

        quotes.state = .off
        XCTAssertTrue(quotes.sendAction(quotes.action, to: quotes.target))
        XCTAssertFalse(defaults.bool(forKey: SettingsKeys.smartQuotes))

        writingTools.state = .on
        XCTAssertTrue(writingTools.sendAction(writingTools.action, to: writingTools.target))
        XCTAssertTrue(defaults.bool(forKey: SettingsKeys.writingTools))

        let labels = allSubviews(of: try XCTUnwrap(controller.window?.contentView))
            .compactMap { $0 as? NSTextField }
        XCTAssertTrue(labels.contains { $0.stringValue.contains("17") && $0.stringValue.contains("Menlo") })
    }

    func testVerticalSidebarSwitchesBetweenFiveSettingsPages() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        let controller = try await makeController(
            shortcutService: ShortcutServiceStub(currentShortcut: .defaultShortcut)
        )
        controller.present()
        defer { controller.close() }

        let buttons = try SettingsContentView.Page.allCases.map {
            try settingsNavigationButton($0, in: controller)
        }
        let navigation = try XCTUnwrap(
            allSubviews(of: try XCTUnwrap(controller.window?.contentView))
                .compactMap { $0 as? NSStackView }
                .first { $0.identifier?.rawValue == "settings-navigation" }
        )
        XCTAssertEqual(buttons.count, 5)
        XCTAssertEqual(navigation.accessibilityRole(), .radioGroup)
        XCTAssertEqual(
            buttons.map { $0.accessibilityLabel() ?? "" },
            ["General", "Pads", "Editor", "Storage", "Updates"]
        )
        XCTAssertTrue(buttons.allSatisfy { $0.title.isEmpty && $0.image == nil })
        let iconMaterials = try buttons.map { button in
            try XCTUnwrap(
                button.subviews.compactMap { $0 as? NSVisualEffectView }.first
            )
        }
        let iconViews = try buttons.map { button in
            try XCTUnwrap(
                allSubviews(of: button).compactMap { $0 as? NSImageView }.first
            )
        }
        let iconTintViews = try buttons.map { button in
            try XCTUnwrap(
                allSubviews(of: button).first {
                    $0.identifier?.rawValue.hasPrefix("settings-navigation-icon-tint-") == true
                }
            )
        }
        XCTAssertTrue(iconViews.allSatisfy { $0.image != nil })
        XCTAssertTrue(iconMaterials.allSatisfy { $0.material == .selection })
        XCTAssertTrue(iconMaterials.allSatisfy { $0.frame.width == $0.frame.height })
        XCTAssertTrue(iconMaterials.allSatisfy { $0.layer?.cornerRadius == 14 })
        XCTAssertEqual(buttons[0].layer?.cornerRadius, 8)
        XCTAssertNotNil(buttons[0].layer?.backgroundColor)
        XCTAssertTrue(buttons.dropFirst().allSatisfy { $0.layer?.backgroundColor == nil })
        for (button, material) in zip(buttons, iconMaterials) {
            let buttonSuperview = try XCTUnwrap(button.superview)
            let materialCenter = NSPoint(x: material.bounds.midX, y: material.bounds.midY)
            let hitPoint = material.convert(materialCenter, to: buttonSuperview)
            XCTAssertTrue(button.hitTest(hitPoint) === button)
        }
        XCTAssertTrue(buttons.allSatisfy { button in
            button.subviews.compactMap { $0 as? NSTextField }.count == 1
        })
        XCTAssertEqual(iconViews[0].contentTintColor, .selectedControlTextColor)
        assertAccentTint(iconTintViews[0], alpha: 0.82)
        assertAccentTint(buttons[0], alpha: 0.20)
        XCTAssertEqual(iconViews[1].contentTintColor, .secondaryLabelColor)
        XCTAssertTrue(buttons.allSatisfy { $0.accessibilityRole() == .radioButton })
        XCTAssertEqual(buttons.map(\.state), [.on, .off, .off, .off, .off])
        XCTAssertTrue(buttons.allSatisfy { $0.frame.width > $0.frame.height })
        XCTAssertLessThan(
            buttons.map(\.frame.midX).max()! - buttons.map(\.frame.midX).min()!,
            1
        )

        let window = try XCTUnwrap(controller.window)
        let hoverEvent = try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ))
        buttons[1].mouseEntered(with: hoverEvent)
        XCTAssertNotNil(buttons[1].layer?.backgroundColor)
        buttons[1].mouseExited(with: hoverEvent)
        XCTAssertNil(buttons[1].layer?.backgroundColor)

        for appearanceName in [NSAppearance.Name.darkAqua, .aqua] {
            window.appearance = NSAppearance(named: appearanceName)
            buttons.forEach { $0.viewDidChangeEffectiveAppearance() }
            XCTAssertNotNil(buttons[0].layer?.backgroundColor)
            XCTAssertTrue(buttons.dropFirst().allSatisfy { $0.layer?.backgroundColor == nil })
        }

        let downArrow = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 125
        ))
        buttons[0].keyDown(with: downArrow)
        XCTAssertEqual(buttons.map(\.state), [.off, .on, .off, .off, .off])
        XCTAssertEqual(iconViews[0].contentTintColor, .secondaryLabelColor)
        XCTAssertEqual(iconViews[1].contentTintColor, .selectedControlTextColor)
        assertAccentTint(iconTintViews[1], alpha: 0.82)
        assertAccentTint(buttons[1], alpha: 0.20)
        XCTAssertNil(buttons[0].layer?.backgroundColor)
        XCTAssertNotNil(buttons[1].layer?.backgroundColor)
        XCTAssertTrue(buttons[1].acceptsFirstResponder)
        XCTAssertFalse(buttons[0].acceptsFirstResponder)

        for (index, button) in buttons.enumerated() {
            button.performClick(nil)
            XCTAssertTrue(controller.window?.firstResponder === button)
            XCTAssertEqual(
                buttons.map(\.state),
                buttons.indices.map { $0 == index ? .on : .off }
            )
            let visiblePages = allSubviews(of: try XCTUnwrap(controller.window?.contentView))
                .filter {
                    $0.identifier?.rawValue.hasPrefix("settings-page-") == true && !$0.isHidden
                }
            XCTAssertEqual(visiblePages.count, 1)
            XCTAssertEqual(
                visiblePages.first?.identifier?.rawValue,
                "settings-page-\(["general", "pads", "editor", "storage", "updates"][index])"
            )
        }

        buttons[3].performClick(nil)
        XCTAssertTrue(controller.window?.firstResponder === buttons[3])
        buttons[3].keyDown(with: downArrow)
        XCTAssertEqual(buttons.map(\.state), [.off, .off, .off, .off, .on])
        XCTAssertTrue(controller.window?.firstResponder === buttons[4])
    }

    func testPadsPageUsesNumberedPadButtonsColorPopupAndRoundedNameField() throws {
        let view = PadCustomizationView(frame: NSRect(x: 0, y: 0, width: 480, height: 180))
        var pads = WorkspaceMetadata.fresh().pads.sorted { $0.position < $1.position }
        pads[0].name = "Inbox"
        pads[0].colorIdentifier = PadColorIdentifier.blue.rawValue
        view.updatePads(pads)
        view.layoutSubtreeIfNeeded()

        let padButtons = view.padSelectorButtons
        XCTAssertEqual(
            padButtons.map(\.title),
            (1...WorkspaceMetadata.padCount).map(String.init)
        )
        XCTAssertEqual(
            padButtons.map { $0.identifier?.rawValue },
            (1...WorkspaceMetadata.padCount).map { "settings-pad-selector-\($0)" }
        )
        XCTAssertFalse(padButtons.contains {
            $0.identifier?.rawValue == "settings-pad-selector-8"
        })
        XCTAssertEqual(padButtons.map { $0.accessibilityRole() }, Array(
            repeating: .radioButton,
            count: WorkspaceMetadata.padCount
        ))
        XCTAssertEqual(
            padButtons.map { $0.accessibilityLabel() ?? "" },
            pads.map(\.accessibilityName)
        )
        XCTAssertEqual(
            padButtons.map(\.state),
            [.on] + Array(repeating: .off, count: WorkspaceMetadata.padCount - 1)
        )
        XCTAssertEqual(
            padButtons.map(\.contentTintColor),
            pads.map { Optional(PanelContentView.padColor(for: $0)) }
        )
        XCTAssertTrue(padButtons.allSatisfy { $0.frame.size == NSSize(width: 32, height: 32) })
        XCTAssertTrue(padButtons.allSatisfy { $0.layer?.cornerRadius == 16 })
        XCTAssertTrue(padButtons.allSatisfy { $0.layer?.backgroundColor != nil })

        let colorSelector = try XCTUnwrap(
            allSubviews(of: view)
                .compactMap { $0 as? NSPopUpButton }
                .first { $0.identifier?.rawValue == "settings-pad-color" }
        )
        let colorItems = try (0..<colorSelector.numberOfItems).map {
            try XCTUnwrap(colorSelector.item(at: $0))
        }

        XCTAssertEqual(colorSelector.accessibilityRole(), .popUpButton)
        XCTAssertEqual(colorSelector.accessibilityLabel(), "Scratchpad 1, Inbox color")
        XCTAssertEqual(colorItems.map(\.title), PadColorIdentifier.allCases.map(\.displayName))
        XCTAssertEqual(
            colorItems.map { $0.identifier?.rawValue },
            PadColorIdentifier.allCases.map { "settings-pad-color-\($0.rawValue)" }
        )
        XCTAssertEqual(
            colorItems.compactMap { $0.representedObject as? String },
            PadColorIdentifier.allCases.map(\.rawValue)
        )
        XCTAssertTrue(colorItems.allSatisfy { $0.image != nil && $0.image?.isTemplate == false })
        XCTAssertEqual(
            colorSelector.selectedItem?.representedObject as? String,
            PadColorIdentifier.blue.rawValue
        )

        let nameField = view.nameField
        XCTAssertTrue(nameField.isEditable)
        XCTAssertTrue(nameField.isBezeled)
        XCTAssertEqual(nameField.bezelStyle, .roundedBezel)
        XCTAssertEqual(nameField.controlSize, .large)
        XCTAssertEqual(nameField.focusRingType, .default)
        XCTAssertGreaterThanOrEqual(nameField.intrinsicContentSize.height, 26)
    }

    func testPadsPageEditsSelectedPadNameAndColorThroughManager() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        let controller = try await makeController(
            shortcutService: ShortcutServiceStub(currentShortcut: .defaultShortcut)
        )
        let manager = PadCustomizationManagerStub()
        controller.connectPadCustomizationManager(manager)
        controller.present()
        defer { controller.close() }

        try settingsNavigationButton(.pads, in: controller).performClick(nil)
        let secondPad = try settingsButton(identifier: "settings-pad-selector-2", in: controller)
        secondPad.performClick(nil)

        let nameField = try settingsLabel(identifier: "settings-pad-name", in: controller)
        XCTAssertTrue(nameField.isEditable)
        XCTAssertEqual(nameField.stringValue, "")
        XCTAssertEqual(nameField.placeholderString, "Scratchpad 2")

        let nameSaved = expectation(description: "pad name saved")
        manager.updateExpectation = nameSaved
        nameField.stringValue = "Research"
        XCTAssertTrue(nameField.sendAction(nameField.action, to: nameField.target))
        await fulfillment(of: [nameSaved], timeout: 1)
        await Task.yield()

        XCTAssertEqual(manager.updates.last?.id, manager.padMetadata[1].id)
        XCTAssertEqual(manager.updates.last?.name, "Research")
        XCTAssertNil(manager.updates.last?.colorIdentifier)
        XCTAssertEqual(secondPad.accessibilityLabel(), "Scratchpad 2, Research")

        let colorSaved = expectation(description: "pad color saved")
        manager.updateExpectation = colorSaved
        let colorSelector = try settingsColorSelector(in: controller)
        let blue = try XCTUnwrap(colorSelector.itemArray.first {
            $0.identifier?.rawValue == "settings-pad-color-blue"
        })
        colorSelector.select(blue)
        XCTAssertTrue(colorSelector.sendAction(colorSelector.action, to: colorSelector.target))
        await fulfillment(of: [colorSaved], timeout: 1)
        await Task.yield()

        XCTAssertEqual(manager.updates.last?.name, "Research")
        XCTAssertEqual(manager.updates.last?.colorIdentifier, PadColorIdentifier.blue.rawValue)
        XCTAssertTrue(colorSelector.selectedItem === blue)
    }

    func testPadsPageRevertsAndReportsPersistenceFailure() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        var errors: [(String, String)] = []
        let controller = try await makeController(
            shortcutService: ShortcutServiceStub(currentShortcut: .defaultShortcut),
            showError: { errors.append(($0, $1)) }
        )
        let manager = PadCustomizationManagerStub()
        manager.error = PadCustomizationError.metadataWriteFailed
        controller.connectPadCustomizationManager(manager)
        controller.present()
        defer { controller.close() }

        try settingsNavigationButton(.pads, in: controller).performClick(nil)
        let attempted = expectation(description: "pad update attempted")
        manager.updateExpectation = attempted
        let nameField = try settingsLabel(identifier: "settings-pad-name", in: controller)
        nameField.stringValue = "Research"
        XCTAssertTrue(nameField.sendAction(nameField.action, to: nameField.target))
        await fulfillment(of: [attempted], timeout: 1)
        await Task.yield()

        XCTAssertEqual(errors.first?.0, "Could not update the scratchpad.")
        XCTAssertEqual(errors.first?.1, PadCustomizationError.metadataWriteFailed.localizedDescription)
        XCTAssertEqual(nameField.stringValue, "")
        XCTAssertTrue(nameField.isEnabled)
        XCTAssertTrue(manager.updates.isEmpty)
    }

    func testPadSwitchDuringNameSaveRemainsOnRequestedPad() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        let controller = try await makeController(
            shortcutService: ShortcutServiceStub(currentShortcut: .defaultShortcut)
        )
        let manager = PadCustomizationManagerStub()
        manager.suspendUpdates = true
        controller.connectPadCustomizationManager(manager)
        controller.present()
        defer { controller.close() }

        try settingsNavigationButton(.pads, in: controller).performClick(nil)
        let started = expectation(description: "pad update started")
        let completed = expectation(description: "pad update completed")
        manager.updateExpectation = started
        manager.updateCompletedExpectation = completed
        let nameField = try settingsLabel(identifier: "settings-pad-name", in: controller)
        nameField.stringValue = "Research"
        XCTAssertTrue(nameField.sendAction(nameField.action, to: nameField.target))
        await fulfillment(of: [started], timeout: 1)

        let secondPad = try settingsButton(identifier: "settings-pad-selector-2", in: controller)
        let colorSelector = try settingsColorSelector(in: controller)
        XCTAssertFalse(nameField.isEnabled)
        XCTAssertFalse(colorSelector.isEnabled)
        XCTAssertTrue(secondPad.isEnabled)
        secondPad.performClick(nil)
        XCTAssertEqual(nameField.placeholderString, "Scratchpad 2")

        manager.resumeUpdate()
        await fulfillment(of: [completed], timeout: 1)
        await Task.yield()

        XCTAssertEqual(nameField.placeholderString, "Scratchpad 2")
        XCTAssertEqual(nameField.stringValue, "")
        XCTAssertEqual(manager.padMetadata[0].name, "Research")
    }

    func testClosingDuringFailedPadSaveDoesNotMutateDismissedSettings() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        var errors: [(String, String)] = []
        let controller = try await makeController(
            shortcutService: ShortcutServiceStub(currentShortcut: .defaultShortcut),
            showError: { errors.append(($0, $1)) }
        )
        let manager = PadCustomizationManagerStub()
        manager.suspendUpdates = true
        manager.error = PadCustomizationError.metadataWriteFailed
        controller.connectPadCustomizationManager(manager)
        controller.present()

        try settingsNavigationButton(.pads, in: controller).performClick(nil)
        let started = expectation(description: "pad update started")
        let completed = expectation(description: "pad update completed")
        manager.updateExpectation = started
        manager.updateCompletedExpectation = completed
        let nameField = try settingsLabel(identifier: "settings-pad-name", in: controller)
        nameField.stringValue = "Research"
        XCTAssertTrue(nameField.sendAction(nameField.action, to: nameField.target))
        await fulfillment(of: [started], timeout: 1)

        controller.close()
        manager.resumeUpdate()
        await fulfillment(of: [completed], timeout: 1)
        await Task.yield()

        XCTAssertTrue(errors.isEmpty)
    }

    func testUpdatesPageChecksOnDemandAndOpensValidatedReleasePage() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        let checked = expectation(description: "update checked")
        let releaseURL = try XCTUnwrap(
            URL(string: "https://github.com/saaivignesh20/BetterTot/releases/tag/v0.2.0")
        )
        var openedURLs: [URL] = []
        let store = WorkspaceStore(root: root)
        _ = try await store.load()
        let controller = SettingsWindowController(
            store: store,
            shortcutService: ShortcutServiceStub(currentShortcut: nil),
            defaults: defaults,
            openURL: { openedURLs.append($0) },
            currentVersion: "0.1.0",
            currentBuild: "7",
            checkForUpdates: {
                checked.fulfill()
                return .updateAvailable(AvailableRelease(
                    version: AppVersion("0.2.0")!,
                    pageURL: releaseURL
                ))
            }
        )
        controller.present()
        defer { controller.close() }

        try settingsNavigationButton(.updates, in: controller).performClick(nil)
        let checkButton = try settingsButton(identifier: "check-for-updates", in: controller)
        let status = try settingsLabel(identifier: "update-status", in: controller)
        let version = try settingsLabel(identifier: "current-version", in: controller)
        let appIcon = try XCTUnwrap(
            allSubviews(of: try XCTUnwrap(controller.window?.contentView))
                .compactMap { $0 as? NSImageView }
                .first { $0.identifier?.rawValue == "bettertot-app-icon" }
        )
        XCTAssertEqual(version.stringValue, "Version 0.1.0 (7)")
        XCTAssertNotNil(appIcon.image)
        XCTAssertEqual(appIcon.image?.size, NSSize(width: 1024, height: 1024))
        XCTAssertEqual(appIcon.accessibilityLabel(), "BetterTot app icon")

        checkButton.performClick(nil)
        await fulfillment(of: [checked], timeout: 1)
        await Task.yield()

        XCTAssertEqual(status.stringValue, "Version 0.2.0 is available.")
        let releaseButton = try settingsButton(identifier: "view-update", in: controller)
        XCTAssertFalse(releaseButton.isHidden)
        releaseButton.performClick(nil)
        XCTAssertEqual(openedURLs, [releaseURL])
    }

    func testUpdatesPagePreventsOverlappingChecksAndReportsNoPublishedRelease() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        var checkCount = 0
        var continuation: CheckedContinuation<UpdateCheckOutcome, Never>?
        let store = WorkspaceStore(root: root)
        _ = try await store.load()
        let controller = SettingsWindowController(
            store: store,
            shortcutService: ShortcutServiceStub(currentShortcut: nil),
            defaults: defaults,
            currentVersion: "0.1.0",
            currentBuild: "8",
            checkForUpdates: {
                checkCount += 1
                return await withCheckedContinuation { continuation = $0 }
            }
        )
        controller.present()
        defer { controller.close() }

        try settingsNavigationButton(.updates, in: controller).performClick(nil)
        let checkButton = try settingsButton(identifier: "check-for-updates", in: controller)
        let status = try settingsLabel(identifier: "update-status", in: controller)
        checkButton.performClick(nil)
        await Task.yield()
        XCTAssertFalse(checkButton.isEnabled)
        _ = checkButton.sendAction(checkButton.action, to: checkButton.target)
        XCTAssertEqual(checkCount, 1)

        continuation?.resume(returning: .noPublishedReleases)
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(status.stringValue, "No published updates are available.")
        XCTAssertTrue(checkButton.isEnabled)
    }

    func testClosingDuringUpdateCheckRestoresIdleState() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        let started = expectation(description: "update check started")
        let store = WorkspaceStore(root: root)
        _ = try await store.load()
        let controller = SettingsWindowController(
            store: store,
            shortcutService: ShortcutServiceStub(currentShortcut: nil),
            defaults: defaults,
            currentVersion: "0.1.0",
            currentBuild: "9",
            checkForUpdates: {
                started.fulfill()
                do {
                    try await Task.sleep(for: .seconds(60))
                    return .noPublishedReleases
                } catch {
                    throw URLError(.cancelled)
                }
            }
        )
        controller.present()

        try settingsNavigationButton(.updates, in: controller).performClick(nil)
        let checkButton = try settingsButton(identifier: "check-for-updates", in: controller)
        let status = try settingsLabel(identifier: "update-status", in: controller)
        checkButton.performClick(nil)
        await fulfillment(of: [started], timeout: 1)

        controller.close()
        await Task.yield()
        controller.present()
        defer { controller.close() }

        XCTAssertEqual(
            status.stringValue,
            "Updates are checked automatically. You can also check now."
        )
        XCTAssertTrue(checkButton.isEnabled)
    }

    func testControllerRefreshesUnavailableShortcutAndBackupSummary() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        let store = WorkspaceStore(root: root)
        _ = try await store.load()
        let controller = SettingsWindowController(
            store: store,
            shortcutService: ShortcutServiceStub(currentShortcut: nil),
            defaults: defaults,
            bundledApp: false
        )
        controller.present()
        defer { controller.close() }

        let views = allSubviews(of: try XCTUnwrap(controller.window?.contentView))
        let buttons = views.compactMap { $0 as? NSButton }
        XCTAssertEqual(
            buttons.first { $0.accessibilityLabel() == "Global shortcut" }?.title,
            "None — click to set"
        )
        let launch = try XCTUnwrap(views.compactMap { $0 as? NSSwitch }
            .first { $0.identifier?.rawValue == "launch-at-login" })
        XCTAssertFalse(launch.isEnabled)
        XCTAssertNotNil(launch.toolTip)

        await controller.refreshBackupSummary()
        XCTAssertEqual(
            try settingsLabel(identifier: "backup-latest-date", in: controller).stringValue,
            "Never"
        )
        XCTAssertEqual(
            try settingsLabel(identifier: "backup-latest-size", in: controller).stringValue,
            "—"
        )
    }

    func testStoragePageRefreshesICloudSummaryAndOpensRepository() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        let store = WorkspaceStore(root: root)
        let snapshot = try await store.load()
        await store.commit(snapshot.metadata.pads[0].id, text: "backup", revision: 1)
        _ = await store.createBackup(.manual)
        var opened: [URL] = []
        let controller = SettingsWindowController(
            store: store,
            shortcutService: ShortcutServiceStub(currentShortcut: nil),
            defaults: defaults,
            openURL: { opened.append($0) }
        )
        controller.present()
        defer { controller.close() }

        try settingsNavigationButton(.storage, in: controller).performClick(nil)
        await controller.refreshBackupSummary()
        XCTAssertNotEqual(
            try settingsLabel(identifier: "backup-latest-date", in: controller).stringValue,
            "Never"
        )
        XCTAssertNotEqual(
            try settingsLabel(identifier: "backup-latest-size", in: controller).stringValue,
            "—"
        )
        try settingsButton(identifier: "open-icloud-backups", in: controller).performClick(nil)
        XCTAssertEqual(opened, [store.backupsDirectory])
    }

    func testLaunchAtLoginActionsUseInjectedBoundaryAndRevertOnFailure() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        let store = WorkspaceStore(root: root)
        _ = try await store.load()
        var changes: [Bool] = []
        var errors: [(String, String)] = []
        let controller = SettingsWindowController(
            store: store,
            shortcutService: ShortcutServiceStub(currentShortcut: nil),
            defaults: defaults,
            bundledApp: true,
            launchAtLoginEnabled: { false },
            setLaunchAtLogin: { enabled in
                changes.append(enabled)
                if !enabled { throw TestError.expected }
            },
            showError: { errors.append(($0, $1)) }
        )
        controller.present()
        defer { controller.close() }
        let launch = try XCTUnwrap(allSubviews(of: try XCTUnwrap(controller.window?.contentView))
            .compactMap { $0 as? NSSwitch }
            .first { $0.identifier?.rawValue == "launch-at-login" })

        XCTAssertTrue(launch.isEnabled)
        XCTAssertEqual(launch.state, .off)
        launch.state = .on
        XCTAssertTrue(launch.sendAction(launch.action, to: launch.target))
        XCTAssertEqual(changes, [true])
        XCTAssertEqual(launch.state, .on)

        launch.state = .off
        XCTAssertTrue(launch.sendAction(launch.action, to: launch.target))
        XCTAssertEqual(changes, [true, false])
        XCTAssertEqual(launch.state, .on, "a failed change restores the prior state")
        XCTAssertEqual(errors.first?.0, "Could not update the login item.")
    }

    func testShortcutRecordingCancelsRejectsAndPersistsValidShortcut() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        let original = Shortcut.defaultShortcut
        let service = ShortcutServiceStub(currentShortcut: original)
        let controller = try await makeController(shortcutService: service)
        defer { controller.close() }
        controller.present()
        let button = try shortcutButton(in: controller)

        button.performClick(nil)
        XCTAssertTrue(button.title.hasPrefix("Type new shortcut"))
        controller.handleShortcutEvent(try keyEvent(in: controller, keyCode: 53))
        XCTAssertEqual(button.title, original.display)

        button.performClick(nil)
        controller.handleShortcutEvent(try keyEvent(in: controller, keyCode: 11, characters: "b"))
        XCTAssertTrue(button.title.hasPrefix("Type new shortcut"), "invalid keys keep recording")
        XCTAssertTrue(service.registrations.isEmpty)
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        XCTAssertEqual(button.title, original.display)

        button.performClick(nil)
        controller.handleShortcutEvent(try keyEvent(
            in: controller,
            keyCode: 11,
            modifiers: [.command],
            characters: "b"
        ))
        let saved = SettingsKeys.loadShortcut(from: defaults)
        XCTAssertEqual(saved.keyCode, 11)
        XCTAssertEqual(saved.display, "⌘B")
        XCTAssertEqual(service.currentShortcut, saved)
        XCTAssertEqual(button.title, "⌘B")
    }

    func testShortcutRegistrationFailureRestoresPreviousShortcutWithoutModalAlert() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        let original = Shortcut.defaultShortcut
        SettingsKeys.save(original, to: defaults)
        let service = ShortcutServiceStub(currentShortcut: original)
        service.rejectKeyCode = 11
        var errors: [(String, String)] = []
        let controller = try await makeController(
            shortcutService: service,
            showError: { errors.append(($0, $1)) }
        )
        defer { controller.close() }
        controller.present()

        let button = try shortcutButton(in: controller)
        button.performClick(nil)
        controller.handleShortcutEvent(try keyEvent(
            in: controller,
            keyCode: 11,
            modifiers: [.command],
            characters: "b"
        ))

        XCTAssertEqual(service.registrations.map(\.keyCode), [11, original.keyCode])
        XCTAssertEqual(service.currentShortcut, original)
        XCTAssertEqual(SettingsKeys.loadShortcut(from: defaults), original)
        XCTAssertEqual(button.title, original.display)
        XCTAssertEqual(errors.first?.0, "That shortcut is unavailable.")
        XCTAssertTrue(errors.first?.1.contains("expected") == true)
    }

    func testFontPanelChangeAndWindowCleanup() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        let store = WorkspaceStore(root: root)
        _ = try await store.load()
        let controller = SettingsWindowController(
            store: store,
            shortcutService: ShortcutServiceStub(currentShortcut: nil),
            defaults: defaults,
            convertFont: { _ in NSFont(name: "Menlo", size: 19)! }
        )
        controller.present()
        let buttons = allSubviews(of: try XCTUnwrap(controller.window?.contentView))
            .compactMap { $0 as? NSButton }

        let selected = try XCTUnwrap(NSFont(name: "Menlo", size: 19))
        controller.changeFont(nil)
        XCTAssertEqual(SettingsKeys.editorFont(in: defaults).fontName, selected.fontName)
        XCTAssertEqual(SettingsKeys.editorFont(in: defaults).pointSize, 19)

        try XCTUnwrap(buttons.first {
            $0.identifier?.rawValue == "change-font"
        }).performClick(nil)
        XCTAssertTrue(NSFontManager.shared.target === controller)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        XCTAssertNil(NSFontManager.shared.target)
        controller.close()
    }

    private func makeController(
        shortcutService: ShortcutServiceStub,
        showError: @escaping (String, String) -> Void = { _, _ in }
    ) async throws -> SettingsWindowController {
        let store = WorkspaceStore(root: root)
        _ = try await store.load()
        return SettingsWindowController(
            store: store,
            shortcutService: shortcutService,
            defaults: defaults,
            showError: showError
        )
    }

    private func shortcutButton(in controller: SettingsWindowController) throws -> NSButton {
        try XCTUnwrap(allSubviews(of: try XCTUnwrap(controller.window?.contentView))
            .compactMap { $0 as? NSButton }
            .first { $0.accessibilityLabel() == "Global shortcut" })
    }

    private func settingsNavigationButton(
        _ page: SettingsContentView.Page,
        in controller: SettingsWindowController
    ) throws -> NSButton {
        try XCTUnwrap(allSubviews(of: try XCTUnwrap(controller.window?.contentView))
            .compactMap { $0 as? NSButton }
            .first {
                $0.identifier?.rawValue == "settings-navigation-\(page.identifier)"
            })
    }

    private func settingsButton(
        identifier: String,
        in controller: SettingsWindowController
    ) throws -> NSButton {
        try XCTUnwrap(allSubviews(of: try XCTUnwrap(controller.window?.contentView))
            .compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == identifier })
    }

    private func settingsColorSelector(
        in controller: SettingsWindowController
    ) throws -> NSPopUpButton {
        try XCTUnwrap(allSubviews(of: try XCTUnwrap(controller.window?.contentView))
            .compactMap { $0 as? NSPopUpButton }
            .first { $0.identifier?.rawValue == "settings-pad-color" })
    }

    private func settingsLabel(
        identifier: String,
        in controller: SettingsWindowController
    ) throws -> NSTextField {
        try XCTUnwrap(allSubviews(of: try XCTUnwrap(controller.window?.contentView))
            .compactMap { $0 as? NSTextField }
            .first { $0.identifier?.rawValue == identifier })
    }

    private func keyEvent(
        in controller: SettingsWindowController,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String = ""
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: try XCTUnwrap(controller.window).windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func assertAccentTint(
        _ view: NSView,
        alpha: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var expected: CGColor?
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            expected = NSColor.controlAccentColor
                .withAlphaComponent(alpha)
                .cgColor
        }
        guard let cgColor = view.layer?.backgroundColor,
              let expected else {
            XCTFail("Expected an accent layer color", file: file, line: line)
            return
        }
        XCTAssertEqual(cgColor, expected, file: file, line: line)
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews.reduce(into: [view]) { result, subview in
            result.append(contentsOf: allSubviews(of: subview))
        }
    }
}

private final class ShortcutServiceStub: GlobalShortcutService {
    private(set) var currentShortcut: Shortcut?
    private(set) var registrations: [Shortcut] = []
    var rejectKeyCode: UInt32?

    init(currentShortcut: Shortcut?) {
        self.currentShortcut = currentShortcut
    }

    func register(_ shortcut: Shortcut) throws {
        registrations.append(shortcut)
        if shortcut.keyCode == rejectKeyCode { throw TestError.expected }
        currentShortcut = shortcut
    }

    func unregister() {
        currentShortcut = nil
    }
}

@MainActor
private final class PadCustomizationManagerStub: PadCustomizationManaging {
    struct Update {
        let id: PadID
        let name: String?
        let colorIdentifier: String?
    }

    private(set) var padMetadata = WorkspaceMetadata.fresh().pads
        .sorted { $0.position < $1.position }
    private(set) var updates: [Update] = []
    var updateExpectation: XCTestExpectation?
    var updateCompletedExpectation: XCTestExpectation?
    var error: Error?
    var suspendUpdates = false
    private var updateContinuation: CheckedContinuation<Void, Never>?

    func updatePadAppearance(
        _ id: PadID,
        name: String?,
        colorIdentifier: String?
    ) async throws -> PadMetadata {
        updateExpectation?.fulfill()
        if suspendUpdates {
            await withCheckedContinuation { updateContinuation = $0 }
        }
        if let error {
            updateCompletedExpectation?.fulfill()
            throw error
        }
        guard let index = padMetadata.firstIndex(where: { $0.id == id }) else {
            throw PadCustomizationError.unknownPad
        }
        var pad = padMetadata[index]
        pad.name = PadMetadata.normalizedName(name)
        pad.colorIdentifier = colorIdentifier
        var updatedPads = padMetadata
        updatedPads[index] = pad
        padMetadata = updatedPads
        updates.append(Update(id: id, name: pad.name, colorIdentifier: colorIdentifier))
        updateCompletedExpectation?.fulfill()
        return pad
    }

    func resumeUpdate() {
        updateContinuation?.resume()
        updateContinuation = nil
    }
}

private enum TestError: LocalizedError {
    case expected

    var errorDescription: String? { "expected test failure" }
}
