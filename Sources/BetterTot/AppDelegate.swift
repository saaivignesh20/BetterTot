import AppKit

@MainActor
protocol SettingsPresenting: AnyObject {
    var onBackupRepositoryDidChange: (@MainActor () -> Void)? { get set }
    func present()
    func present(_ page: SettingsContentView.Page)
    func connectPadCustomizationManager(_ manager: any PadCustomizationManaging)
}

extension SettingsPresenting {
    func present(_ page: SettingsContentView.Page) { present() }
    func connectPadCustomizationManager(_ manager: any PadCustomizationManaging) {}
}

extension SettingsWindowController: SettingsPresenting {}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    struct Dependencies {
        let defaults: UserDefaults
        let makeStore: @MainActor () -> WorkspaceStore
        let loadStore: @MainActor (WorkspaceStore) async throws -> WorkspaceSnapshot
        let makeShortcutService: @MainActor (@escaping () -> Void) -> GlobalShortcutService
        let scheduleMainAction: (@escaping @MainActor () -> Void) -> Void
        let makeSettingsController: @MainActor (WorkspaceStore, GlobalShortcutService) -> SettingsPresenting
        let currentEvent: @MainActor () -> NSEvent?
        let presentStatusMenu: @MainActor (NSStatusItem) -> Void
        let presentShortcutFailureAlert: @MainActor (NSAlert) -> Void
        let isBundledApp: @MainActor () -> Bool
        let currentVersion: @MainActor () -> String
        let automaticUpdateCheck: @MainActor () async throws -> UpdateCheckOutcome
        let openURL: @MainActor (URL) -> Void
        let terminateApplication: @MainActor () -> Void
        let flushPanel: @MainActor (PanelController) async -> FlushResult
        let markCleanShutdown: @MainActor (WorkspaceStore) async -> Void
        let replyToTermination: @MainActor (NSApplication, Bool) -> Void

        init(
            defaults: UserDefaults = .standard,
            makeStore: @escaping @MainActor () -> WorkspaceStore = {
                let localRoot = WorkspaceStore.defaultRoot()
                let backupResolver = PrivateICloudDriveBackupLocationResolver()
                let legacyMirror = SettingsKeys.storedLegacyBackupDirectory().map {
                    $0.appendingPathComponent("BetterTot Backups", isDirectory: true)
                }
                var legacyBackupDirectories = [
                    localRoot.appendingPathComponent("Backups", isDirectory: true)
                ]
                if let legacyMirror {
                    legacyBackupDirectories.append(legacyMirror)
                }
                return WorkspaceStore(
                    root: localRoot,
                    backupRepositoryLocationResolver: backupResolver,
                    legacyBackupDirectories: legacyBackupDirectories
                )
            },
            loadStore: @escaping @MainActor (WorkspaceStore) async throws -> WorkspaceSnapshot = {
                try $0.load()
            },
            makeShortcutService: @escaping @MainActor (@escaping () -> Void) -> GlobalShortcutService = {
                CarbonGlobalShortcutService(onPress: $0)
            },
            scheduleMainAction: @escaping (@escaping @MainActor () -> Void) -> Void = { action in
                Task { @MainActor in action() }
            },
            makeSettingsController: @escaping @MainActor (
                WorkspaceStore,
                GlobalShortcutService
            ) -> SettingsPresenting = {
                SettingsWindowController(store: $0, shortcutService: $1)
            },
            currentEvent: @escaping @MainActor () -> NSEvent? = { NSApp.currentEvent },
            presentStatusMenu: @escaping @MainActor (NSStatusItem) -> Void = {
                $0.button?.performClick(nil)
            },
            presentShortcutFailureAlert: @escaping @MainActor (NSAlert) -> Void = { alert in
                NSApp.activate(ignoringOtherApps: true)
                alert.window.level = .floating
                alert.window.center()
                alert.window.makeKeyAndOrderFront(nil)
            },
            isBundledApp: @escaping @MainActor () -> Bool = {
                SettingsWindowController.isBundledApp
            },
            currentVersion: @escaping @MainActor () -> String = {
                SettingsWindowController.bundleVersion
            },
            automaticUpdateCheck: @escaping @MainActor () async throws -> UpdateCheckOutcome = {
                guard let version = AppVersion(SettingsWindowController.bundleVersion) else {
                    throw UpdateCheckError.invalidResponse
                }
                return try await GitHubUpdateChecker.live().check(currentVersion: version)
            },
            openURL: @escaping @MainActor (URL) -> Void = {
                _ = NSWorkspace.shared.open($0)
            },
            terminateApplication: @escaping @MainActor () -> Void = { NSApp.terminate(nil) },
            flushPanel: @escaping @MainActor (PanelController) async -> FlushResult = {
                await $0.flushAll()
            },
            markCleanShutdown: @escaping @MainActor (WorkspaceStore) async -> Void = {
                $0.markCleanShutdown()
            },
            replyToTermination: @escaping @MainActor (NSApplication, Bool) -> Void = {
                $0.reply(toApplicationShouldTerminate: $1)
            }
        ) {
            self.defaults = defaults
            self.makeStore = makeStore
            self.loadStore = loadStore
            self.makeShortcutService = makeShortcutService
            self.scheduleMainAction = scheduleMainAction
            self.makeSettingsController = makeSettingsController
            self.currentEvent = currentEvent
            self.presentStatusMenu = presentStatusMenu
            self.presentShortcutFailureAlert = presentShortcutFailureAlert
            self.isBundledApp = isBundledApp
            self.currentVersion = currentVersion
            self.automaticUpdateCheck = automaticUpdateCheck
            self.openURL = openURL
            self.terminateApplication = terminateApplication
            self.flushPanel = flushPanel
            self.markCleanShutdown = markCleanShutdown
            self.replyToTermination = replyToTermination
        }
    }

    private(set) var statusItem: NSStatusItem?
    private(set) var panelController: PanelController?
    private(set) var shortcutService: GlobalShortcutService?
    private(set) var store: WorkspaceStore?
    private(set) var settingsController: SettingsPresenting?
    private(set) var statusMenu: NSMenu?
    private(set) var shortcutFailureAlert: NSAlert?
    private(set) var launchTask: Task<Void, Never>?
    private(set) var automaticUpdateTask: Task<Void, Never>?
    private(set) var backupPreflightTask: Task<Void, Never>?
    private var isTerminating = false
    private var availableUpdate: AvailableRelease?
    private var backupNeedsAttention = false
    private let dependencies: Dependencies

    init(dependencies: Dependencies = Dependencies()) {
        self.dependencies = dependencies
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        dependencies.defaults.register(defaults: SettingsKeys.defaults)
        installMainMenu()
        let store = dependencies.makeStore()
        // Stay invisible until recovery finishes (plan §14.2).
        launchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await dependencies.loadStore(store)
                self.setUp(store: store, snapshot: snapshot)
            } catch {
                let diagnostic = error as NSError
                NSLog("BetterTot: storage initialization failed (%@:%ld)",
                      diagnostic.domain, diagnostic.code)
                dependencies.terminateApplication()
            }
        }
    }

    private func setUp(store: WorkspaceStore, snapshot: WorkspaceSnapshot) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.make()
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        let controller = PanelController(
            statusItem: item,
            store: store,
            snapshot: snapshot,
            defaults: dependencies.defaults
        )
        controller.onOpenSettings = { [weak self] in self?.openSettings(nil) }
        panelController = controller
        statusMenu = buildStatusMenu(controller: controller)

        let scheduleMainAction = dependencies.scheduleMainAction
        let service = dependencies.makeShortcutService { [weak self] in
            scheduleMainAction {
                self?.panelController?.toggle(reason: .globalShortcutToggle)
            }
        }
        do {
            try service.register(SettingsKeys.loadShortcut(from: dependencies.defaults))
        } catch {
            let diagnostic = error as NSError
            NSLog("BetterTot: shortcut registration failed (%@:%ld)",
                  diagnostic.domain, diagnostic.code)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Global shortcut unavailable"
            alert.informativeText = error.localizedDescription
                + " Choose a different shortcut in Settings."
            shortcutFailureAlert = alert
            dependencies.presentShortcutFailureAlert(alert)
        }
        shortcutService = service
        self.store = store
        startAutomaticUpdateCheckIfDue(controller: controller)
        startBackupPreflight(store: store, controller: controller)
    }

    // A minimal main menu so app-wide key equivalents (⌘Q, ⌘,) and standard
    // edit commands work whenever the app is active with any window key —
    // e.g. the settings window. The nonactivating panel still routes its own
    // keys in performKeyEquivalent because the app is usually inactive there.
    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit BetterTot",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    private func buildStatusMenu(controller: PanelController) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, target: AnyObject, key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = target
            menu.addItem(item)
        }
        if backupNeedsAttention {
            add(
                "iCloud Backup Needs Attention...",
                #selector(openStorageSettings),
                target: self
            )
            menu.addItem(.separator())
        }
        if let availableUpdate {
            add(
                "Update to BetterTot \(availableUpdate.version)...",
                #selector(openAvailableUpdate),
                target: self
            )
            menu.addItem(.separator())
        }
        add("Import Into Current Pad…", #selector(PanelController.importIntoCurrentPad(_:)), target: controller)
        add("Export Current Pad…", #selector(PanelController.exportCurrentPad(_:)), target: controller)
        add("Export All Pads…", #selector(PanelController.exportAllPads(_:)), target: controller)
        menu.addItem(.separator())
        add("Settings…", #selector(openSettings), target: self, key: ",")
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit BetterTot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    private func startAutomaticUpdateCheckIfDue(controller: PanelController) {
        let state = AutomaticUpdateCheckState(defaults: dependencies.defaults)
        guard AppVersion(dependencies.currentVersion()) != nil,
              AutomaticUpdateCheckPolicy.shouldCheck(
                for: .automatic,
                isBundledApp: dependencies.isBundledApp(),
                now: Date(),
                lastSuccessfulAutomaticCheck: state.lastSuccessfulCheckDate
              ) else { return }

        let check = dependencies.automaticUpdateCheck
        automaticUpdateTask = Task { @MainActor [weak self, weak controller] in
            defer { self?.automaticUpdateTask = nil }
            do {
                let outcome = try await check()
                guard !Task.isCancelled, let self else { return }
                state.recordSuccessfulCheck(.automatic, at: Date())
                if case .updateAvailable(let release) = outcome {
                    availableUpdate = release
                    if let controller {
                        statusMenu = buildStatusMenu(controller: controller)
                    }
                }
            } catch {
                let diagnostic = error as NSError
                NSLog(
                    "BetterTot: automatic update check failed (%@:%ld)",
                    diagnostic.domain,
                    diagnostic.code
                )
            }
        }
    }

    @objc private func openAvailableUpdate() {
        guard let availableUpdate else { return }
        dependencies.openURL(availableUpdate.pageURL)
    }

    private func startBackupPreflight(store: WorkspaceStore, controller: PanelController) {
        backupPreflightTask = Task { @MainActor [weak self, weak controller] in
            defer { self?.backupPreflightTask = nil }
            let summary = await store.backupRepositorySummary()
            guard !Task.isCancelled, let self else { return }
            switch summary.health {
            case .ready:
                backupNeedsAttention = false
            case .unavailable, .blocked:
                backupNeedsAttention = true
            }
            if let controller {
                statusMenu = buildStatusMenu(controller: controller)
            }
        }
    }

    @objc private func openStorageSettings() {
        presentSettings(.storage)
    }

    @objc func statusItemClicked() {
        let event = dependencies.currentEvent()
        let isMenuGesture = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)
        if isMenuGesture, let statusItem, let statusMenu {
            // standard trick: attach the menu, click, detach so left-click stays a toggle
            statusItem.menu = statusMenu
            dependencies.presentStatusMenu(statusItem)
            statusItem.menu = nil
        } else {
            panelController?.toggle(reason: .statusItemToggle)
        }
    }

    @objc func openSettings(_ sender: Any?) {
        presentSettings(nil)
    }

    private func presentSettings(_ page: SettingsContentView.Page?) {
        guard let store, let shortcutService, let panelController else { return }
        if settingsController == nil {
            let controller = dependencies.makeSettingsController(store, shortcutService)
            controller.connectPadCustomizationManager(panelController)
            controller.onBackupRepositoryDidChange = { [weak self] in
                guard let self, let store = self.store,
                      let panelController = self.panelController else { return }
                self.startBackupPreflight(store: store, controller: panelController)
            }
            settingsController = controller
        }
        if let page {
            settingsController?.present(page)
        } else {
            settingsController?.present()
        }
    }

    // Async flush before termination; never mark clean if a save may be pending.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let panelController, let store else { return .terminateNow }
        // Re-entry (⌘Q key-repeat) must not abort the in-flight flush; the
        // first request's pending reply completes termination.
        guard !isTerminating else { return .terminateCancel }
        isTerminating = true
        Task { @MainActor in
            let flushResult = await dependencies.flushPanel(panelController)
            if flushResult == .failed {
                isTerminating = false
                dependencies.replyToTermination(sender, false)
                return
            }
            if flushResult == .committed {
                await dependencies.markCleanShutdown(store)
            }
            dependencies.replyToTermination(sender, true)
        }
        return .terminateLater
    }
}
