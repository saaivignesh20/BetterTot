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
        XCTAssertEqual(defaults.double(forKey: SettingsKeys.fontSize), 14)
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
        XCTAssertEqual(spell.state, .off)
        XCTAssertEqual(quotes.state, .on)
        XCTAssertEqual(dashes.state, .on)
        XCTAssertEqual(buttons.first { $0.accessibilityLabel() == "Global shortcut" }?.title, "⌥⌘F13")

        quotes.state = .off
        XCTAssertTrue(quotes.sendAction(quotes.action, to: quotes.target))
        XCTAssertFalse(defaults.bool(forKey: SettingsKeys.smartQuotes))

        let labels = allSubviews(of: try XCTUnwrap(controller.window?.contentView))
            .compactMap { $0 as? NSTextField }
        XCTAssertTrue(labels.contains { $0.stringValue.contains("17") && $0.stringValue.contains("Menlo") })
    }

    func testTopNavigationSwitchesBetweenFourSettingsPages() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        let controller = try await makeController(
            shortcutService: ShortcutServiceStub(currentShortcut: .defaultShortcut)
        )
        controller.present()
        defer { controller.close() }

        let views = allSubviews(of: try XCTUnwrap(controller.window?.contentView))
        let navigation = try XCTUnwrap(views.compactMap { $0 as? NSSegmentedControl }
            .first { $0.identifier?.rawValue == "settings-navigation" })
        XCTAssertEqual(navigation.segmentCount, 4)
        XCTAssertEqual(navigation.selectedSegment, 0)
        XCTAssertEqual(
            (0..<navigation.segmentCount).compactMap { navigation.label(forSegment: $0) },
            ["General", "Editor", "Storage", "Updates"]
        )

        for index in 0..<navigation.segmentCount {
            navigation.selectedSegment = index
            XCTAssertTrue(navigation.sendAction(navigation.action, to: navigation.target))
            let visiblePages = allSubviews(of: try XCTUnwrap(controller.window?.contentView))
                .filter {
                    $0.identifier?.rawValue.hasPrefix("settings-page-") == true && !$0.isHidden
                }
            XCTAssertEqual(visiblePages.count, 1)
            XCTAssertEqual(
                visiblePages.first?.identifier?.rawValue,
                "settings-page-\(["general", "editor", "storage", "updates"][index])"
            )
        }
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

        let navigation = try settingsNavigation(in: controller)
        navigation.selectedSegment = 3
        XCTAssertTrue(navigation.sendAction(navigation.action, to: navigation.target))
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

        let checkButton = try settingsButton(identifier: "check-for-updates", in: controller)
        let status = try settingsLabel(identifier: "update-status", in: controller)
        checkButton.performClick(nil)
        await fulfillment(of: [started], timeout: 1)

        controller.close()
        await Task.yield()
        controller.present()
        defer { controller.close() }

        XCTAssertEqual(status.stringValue, "Updates are checked only when requested.")
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

        let summary = try XCTUnwrap(views.compactMap { $0 as? NSTextField }
            .first { $0.stringValue.hasPrefix("Backups:") })
        await controller.refreshBackupSummary()
        XCTAssertTrue(summary.stringValue.contains("Hourly: 0 (keeps 24)"))
        XCTAssertTrue(summary.stringValue.contains("Daily: 0 (keeps 14)"))
        XCTAssertTrue(summary.stringValue.contains("Manual: 0"))
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

    func testFontPanelChangeWorkspaceActionAndWindowCleanup() async throws {
        defaults.register(defaults: SettingsKeys.defaults)
        let store = WorkspaceStore(root: root)
        _ = try await store.load()
        var openedURLs: [URL] = []
        let controller = SettingsWindowController(
            store: store,
            shortcutService: ShortcutServiceStub(currentShortcut: nil),
            defaults: defaults,
            openURL: { openedURLs.append($0) },
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
        try XCTUnwrap(buttons.first {
            $0.identifier?.rawValue == "open-backup-folder"
        }).performClick(nil)
        XCTAssertEqual(openedURLs, [store.backupsDirectory])

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

    private func settingsNavigation(
        in controller: SettingsWindowController
    ) throws -> NSSegmentedControl {
        try XCTUnwrap(allSubviews(of: try XCTUnwrap(controller.window?.contentView))
            .compactMap { $0 as? NSSegmentedControl }
            .first { $0.identifier?.rawValue == "settings-navigation" })
    }

    private func settingsButton(
        identifier: String,
        in controller: SettingsWindowController
    ) throws -> NSButton {
        try XCTUnwrap(allSubviews(of: try XCTUnwrap(controller.window?.contentView))
            .compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == identifier })
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

private enum TestError: LocalizedError {
    case expected

    var errorDescription: String? { "expected test failure" }
}
