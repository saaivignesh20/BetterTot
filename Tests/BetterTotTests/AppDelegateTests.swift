import AppKit
import XCTest
@testable import BetterTot

@MainActor
final class AppDelegateTests: XCTestCase {
    private var root: URL!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var originalMainMenu: NSMenu?
    private var delegate: AppDelegate?

    override func setUpWithError() throws {
        _ = NSApplication.shared
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettertot-app-delegate-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "BetterTot.AppDelegateTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        originalMainMenu = NSApp.mainMenu
    }

    override func tearDown() async throws {
        delegate?.panelController?.dismiss(reason: .explicitClose)
        await Task.yield()
        if let store = delegate?.store {
            _ = await store.currentMetadata()
        }
        delegate?.shortcutFailureAlert?.window.close()
        if let statusItem = delegate?.statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        delegate = nil
        NSApp.mainMenu = originalMainMenu
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }

    func testSuccessfulLaunchInstallsMainAndStatusMenus() async throws {
        let shortcut = ShortcutServiceSpy()
        delegate = makeDelegate(shortcutService: shortcut)

        delegate?.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await delegate?.launchTask?.value

        XCTAssertTrue(defaults.bool(forKey: SettingsKeys.spellChecking))
        XCTAssertNotNil(delegate?.store)
        XCTAssertNotNil(delegate?.panelController)
        XCTAssertTrue(delegate?.shortcutService === shortcut)
        XCTAssertEqual(shortcut.registeredShortcuts, [.defaultShortcut])

        let statusItem = try XCTUnwrap(delegate?.statusItem)
        XCTAssertEqual(statusItem.button?.action, #selector(AppDelegate.statusItemClicked))
        XCTAssertTrue(statusItem.button?.target === delegate)
        let statusImage = try XCTUnwrap(statusItem.button?.image)
        XCTAssertTrue(statusImage.isTemplate)
        XCTAssertEqual(statusImage.size, NSSize(width: 18, height: 18))
        XCTAssertEqual(statusImage.accessibilityDescription, "BetterTot scratchpad")
        XCTAssertTrue(statusImage.representations.contains { $0.pixelsWide == 240 })
        let bitmap = try XCTUnwrap(
            statusImage.representations.compactMap { $0 as? NSBitmapImageRep }.first
        )
        XCTAssertEqual(bitmap.colorAt(x: 0, y: 0)?.alphaComponent, 0)
        XCTAssertGreaterThan(bitmap.colorAt(x: 120, y: 120)?.alphaComponent ?? 0, 0.9)
        let centroid = alphaCentroid(of: bitmap)
        XCTAssertEqual(centroid.x, 119.5, accuracy: 2)
        XCTAssertEqual(centroid.y, 119.5, accuracy: 2)

        let appMenu = try XCTUnwrap(NSApp.mainMenu?.items.first?.submenu)
        XCTAssertEqual(appMenu.items.map(\.title), ["Settings…", "", "Quit BetterTot"])
        XCTAssertTrue(appMenu.items[0].target === delegate)
        XCTAssertEqual(appMenu.items[0].keyEquivalent, ",")
        XCTAssertEqual(appMenu.items[2].keyEquivalent, "q")

        let editMenu = try XCTUnwrap(NSApp.mainMenu?.items.last?.submenu)
        XCTAssertEqual(editMenu.title, "Edit")
        XCTAssertEqual(
            editMenu.items.map(\.title),
            ["Undo", "Redo", "", "Cut", "Copy", "Paste", "Select All"])

        let statusMenu = try XCTUnwrap(delegate?.statusMenu)
        XCTAssertEqual(statusMenu.items.map(\.title), [
            "Settings…", "", "Create Backup Now", "Open Backup Folder", "Restore Backup…", "",
            "Import Into Current Pad…", "Export Current Pad…", "Export All Pads…", "",
            "Quit BetterTot",
        ])
        XCTAssertTrue(statusMenu.items[0].target === delegate)
        XCTAssertTrue(statusMenu.items[2].target === delegate?.panelController)
        XCTAssertTrue(statusMenu.items.last?.target === NSApp)
    }

    private func alphaCentroid(of bitmap: NSBitmapImageRep) -> NSPoint {
        var weightedX = 0.0
        var weightedY = 0.0
        var totalAlpha = 0.0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                weightedX += Double(x) * alpha
                weightedY += Double(y) * alpha
                totalAlpha += alpha
            }
        }
        return NSPoint(x: weightedX / totalAlpha, y: weightedY / totalAlpha)
    }

    func testShortcutRegistrationFailureReportsNonblockingAlertAndCompletesSetup() async throws {
        let shortcut = ShortcutServiceSpy(error: TestError.shortcutUnavailable)
        var presentedAlerts: [NSAlert] = []
        delegate = makeDelegate(
            shortcutService: shortcut,
            presentShortcutFailureAlert: { presentedAlerts.append($0) })

        delegate?.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await delegate?.launchTask?.value

        XCTAssertEqual(shortcut.registeredShortcuts, [.defaultShortcut])
        XCTAssertNotNil(delegate?.store)
        XCTAssertNotNil(delegate?.panelController)
        XCTAssertTrue(delegate?.shortcutService === shortcut)
        let alert = try XCTUnwrap(presentedAlerts.first)
        XCTAssertTrue(delegate?.shortcutFailureAlert === alert)
        XCTAssertEqual(alert.messageText, "Global shortcut unavailable")
        XCTAssertTrue(alert.informativeText.contains("test shortcut unavailable"))
        XCTAssertFalse(alert.window.isVisible, "the injected presenter must not block or display UI")
    }

    func testStatusItemLeftClickTogglesPanelAndRightClickPresentsMenu() async throws {
        var event: NSEvent?
        var presentedItem: NSStatusItem?
        var presentedMenu: NSMenu?
        delegate = makeDelegate(
            currentEvent: { event },
            presentStatusMenu: { item in
                presentedItem = item
                presentedMenu = item.menu
            })
        delegate?.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await delegate?.launchTask?.value

        let panel = try XCTUnwrap(delegate?.panelController?.textView.window)
        XCTAssertFalse(panel.isVisible)
        delegate?.statusItemClicked()
        XCTAssertTrue(panel.isVisible)
        delegate?.statusItemClicked()
        XCTAssertFalse(panel.isVisible)

        event = try mouseEvent(type: .rightMouseUp)
        delegate?.statusItemClicked()
        XCTAssertTrue(presentedItem === delegate?.statusItem)
        XCTAssertTrue(presentedMenu === delegate?.statusMenu)
        XCTAssertNil(delegate?.statusItem?.menu, "menu attachment must remain temporary")
        XCTAssertFalse(panel.isVisible)

        event = try mouseEvent(type: .leftMouseUp, modifiers: [.control])
        delegate?.statusItemClicked()
        XCTAssertTrue(presentedMenu === delegate?.statusMenu)
        XCTAssertFalse(panel.isVisible)

        (delegate?.shortcutService as? ShortcutServiceSpy)?.press()
        XCTAssertTrue(panel.isVisible)
    }

    func testSettingsAreBuiltOnceAndCanBeOpenedFromPanelCallback() async {
        let settings = SettingsPresenterSpy()
        var factoryCalls = 0
        delegate = makeDelegate(makeSettingsController: { _, _ in
            factoryCalls += 1
            return settings
        })

        delegate?.openSettings(nil)
        XCTAssertEqual(factoryCalls, 0, "settings require completed application setup")

        delegate?.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await delegate?.launchTask?.value
        delegate?.openSettings(nil)
        delegate?.panelController?.onOpenSettings?()

        XCTAssertEqual(factoryCalls, 1)
        XCTAssertEqual(settings.presentationCount, 2)
        XCTAssertTrue(delegate?.settingsController === settings)
    }

    func testTerminationWithoutSetupIsImmediate() {
        delegate = makeDelegate()

        XCTAssertEqual(delegate?.applicationShouldTerminate(NSApp), .terminateNow)
    }

    func testTerminationFlushesThenMarksCleanAndRepliesOnce() async {
        var lifecycleEvents: [String] = []
        let replied = expectation(description: "termination reply")
        delegate = makeDelegate(
            flushPanel: { _ in
                lifecycleEvents.append("flush")
                return .committed
            },
            markCleanShutdown: { _ in lifecycleEvents.append("clean") },
            replyToTermination: { application, shouldTerminate in
                XCTAssertTrue(application === NSApp)
                XCTAssertTrue(shouldTerminate)
                lifecycleEvents.append("reply")
                replied.fulfill()
            })
        delegate?.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await delegate?.launchTask?.value

        XCTAssertEqual(delegate?.applicationShouldTerminate(NSApp), .terminateLater)
        XCTAssertEqual(delegate?.applicationShouldTerminate(NSApp), .terminateCancel)
        await fulfillment(of: [replied], timeout: 1)

        XCTAssertEqual(lifecycleEvents, ["flush", "clean", "reply"])
    }

    func testTerminationCancelsWhenNothingCanBePersisted() async {
        var cleanMarkerCount = 0
        var replies: [Bool] = []
        let replied = expectation(description: "termination cancellation reply")
        delegate = makeDelegate(
            flushPanel: { _ in .failed },
            markCleanShutdown: { _ in cleanMarkerCount += 1 },
            replyToTermination: { _, shouldTerminate in
                replies.append(shouldTerminate)
                replied.fulfill()
            }
        )
        delegate?.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await delegate?.launchTask?.value

        XCTAssertEqual(delegate?.applicationShouldTerminate(NSApp), .terminateLater)
        await fulfillment(of: [replied], timeout: 1)

        XCTAssertEqual(replies, [false])
        XCTAssertEqual(cleanMarkerCount, 0)
    }

    func testJournaledTerminationDoesNotWriteCleanMarker() async {
        var cleanMarkerCount = 0
        let replied = expectation(description: "recoverable termination reply")
        delegate = makeDelegate(
            flushPanel: { _ in .journaled },
            markCleanShutdown: { _ in cleanMarkerCount += 1 },
            replyToTermination: { _, shouldTerminate in
                XCTAssertTrue(shouldTerminate)
                replied.fulfill()
            }
        )
        delegate?.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await delegate?.launchTask?.value

        XCTAssertEqual(delegate?.applicationShouldTerminate(NSApp), .terminateLater)
        await fulfillment(of: [replied], timeout: 1)

        XCTAssertEqual(cleanMarkerCount, 0)
    }

    func testLaunchFailureTerminatesThroughInjectedBoundaryWithoutSettingUpUI() async {
        var terminationCount = 0
        delegate = makeDelegate(
            loadStore: { _ in throw TestError.storageUnavailable },
            terminateApplication: { terminationCount += 1 })

        delegate?.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        await delegate?.launchTask?.value

        XCTAssertEqual(terminationCount, 1)
        XCTAssertNil(delegate?.statusItem)
        XCTAssertNil(delegate?.panelController)
        XCTAssertNil(delegate?.store)
    }

    private func makeDelegate(
        shortcutService: ShortcutServiceSpy = ShortcutServiceSpy(),
        loadStore: @escaping @MainActor (WorkspaceStore) async throws -> WorkspaceSnapshot = {
            try $0.load()
        },
        currentEvent: @escaping @MainActor () -> NSEvent? = { nil },
        presentStatusMenu: @escaping @MainActor (NSStatusItem) -> Void = { _ in },
        presentShortcutFailureAlert: @escaping @MainActor (NSAlert) -> Void = { _ in },
        makeSettingsController: @escaping @MainActor (
            WorkspaceStore,
            GlobalShortcutService
        ) -> SettingsPresenting = {
            SettingsWindowController(store: $0, shortcutService: $1)
        },
        terminateApplication: @escaping @MainActor () -> Void = {},
        flushPanel: @escaping @MainActor (PanelController) async -> FlushResult = { await $0.flushAll() },
        markCleanShutdown: @escaping @MainActor (WorkspaceStore) async -> Void = { $0.markCleanShutdown() },
        replyToTermination: @escaping @MainActor (NSApplication, Bool) -> Void = { _, _ in }
    ) -> AppDelegate {
        AppDelegate(dependencies: .init(
            defaults: defaults,
            makeStore: { WorkspaceStore(root: self.root) },
            loadStore: loadStore,
            makeShortcutService: { callback in
                shortcutService.onPress = callback
                return shortcutService
            },
            scheduleMainAction: { $0() },
            makeSettingsController: makeSettingsController,
            currentEvent: currentEvent,
            presentStatusMenu: presentStatusMenu,
            presentShortcutFailureAlert: presentShortcutFailureAlert,
            terminateApplication: terminateApplication,
            flushPanel: flushPanel,
            markCleanShutdown: markCleanShutdown,
            replyToTermination: replyToTermination
        ))
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
    }
}

private enum TestError: LocalizedError {
    case shortcutUnavailable
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .shortcutUnavailable: "test shortcut unavailable"
        case .storageUnavailable: "test storage unavailable"
        }
    }
}

private final class ShortcutServiceSpy: GlobalShortcutService {
    private(set) var currentShortcut: Shortcut?
    private(set) var registeredShortcuts: [Shortcut] = []
    private let error: Error?
    fileprivate var onPress: (() -> Void)?

    init(error: Error? = nil) {
        self.error = error
    }

    func register(_ shortcut: Shortcut) throws {
        registeredShortcuts.append(shortcut)
        if let error { throw error }
        currentShortcut = shortcut
    }

    func unregister() {
        currentShortcut = nil
    }

    func press() {
        onPress?()
    }
}

@MainActor
private final class SettingsPresenterSpy: SettingsPresenting {
    private(set) var presentationCount = 0

    func present() {
        presentationCount += 1
    }
}
