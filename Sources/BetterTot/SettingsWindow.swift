import AppKit
import ServiceManagement

enum SettingsKeys {
    static let spellChecking = "spellChecking"
    static let smartQuotes = "smartQuotes"
    static let smartDashes = "smartDashes"
    static let writingTools = "writingTools"
    static let fontName = "editorFontName"
    static let fontSize = "editorFontSize"
    static let globalShortcut = "globalShortcut"
    static let backupMirrorEnabled = "backupMirrorEnabled"
    static let backupMirrorDirectory = "backupMirrorDirectory"

    static func loadShortcut(from defaults: UserDefaults = .standard) -> Shortcut {
        guard let data = defaults.data(forKey: globalShortcut),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data),
              Shortcut.isValid(
                keyCode: shortcut.keyCode,
                carbonModifiers: shortcut.carbonModifiers
              ) else {
            return .defaultShortcut
        }
        return shortcut
    }

    static func save(_ shortcut: Shortcut, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: globalShortcut)
        }
    }

    static func save(_ font: NSFont, to defaults: UserDefaults = .standard) {
        defaults.set(font.fontName, forKey: fontName)
        defaults.set(Double(font.pointSize), forKey: fontSize)
    }

    static func saveBackupMirrorDirectory(
        _ directory: URL,
        to defaults: UserDefaults = .standard
    ) {
        guard directory.isFileURL, directory.path != "/" else {
            defaults.removeObject(forKey: backupMirrorDirectory)
            return
        }
        defaults.set(directory.standardizedFileURL.path, forKey: backupMirrorDirectory)
    }

    static func storedBackupMirrorDirectory(
        in defaults: UserDefaults = .standard
    ) -> URL? {
        guard let path = defaults.string(forKey: backupMirrorDirectory),
              !path.isEmpty,
              path != "/" else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    static func activeBackupMirrorDirectory(
        in defaults: UserDefaults = .standard
    ) -> URL? {
        guard defaults.bool(forKey: backupMirrorEnabled) else { return nil }
        return storedBackupMirrorDirectory(in: defaults)
    }

    static let defaults: [String: Any] = [
        spellChecking: true,
        smartQuotes: false,
        smartDashes: false,
        writingTools: false,
        fontName: "AmericanTypewriter",
        fontSize: 14.0,
        backupMirrorEnabled: false,
    ]

    static var editorFont: NSFont {
        editorFont(in: .standard)
    }

    static func editorFont(in defaults: UserDefaults) -> NSFont {
        let size = defaults.double(forKey: fontSize)
        if let name = defaults.string(forKey: fontName),
           let font = NSFont(name: name, size: size) {
            return font
        }
        return .systemFont(ofSize: size)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private static let idleUpdateStatus = "Updates are checked only when requested."

    private let store: WorkspaceStore
    private let shortcutService: GlobalShortcutService
    private let defaults: UserDefaults
    private let bundledApp: Bool
    private let launchAtLoginEnabled: @MainActor () -> Bool
    private let setLaunchAtLogin: @MainActor (Bool) throws -> Void
    private let openURL: @MainActor (URL) -> Void
    private let showError: @MainActor (String, String) -> Void
    private let convertFont: @MainActor (NSFont) -> NSFont
    private let chooseBackupMirrorDirectory: @MainActor () -> URL?
    private let checkForUpdates: @MainActor () async throws -> UpdateCheckOutcome
    private let currentVersion: String
    private let currentBuild: String
    private let settingsView = SettingsContentView()

    private var recordingMonitor: Any?
    private var updateTask: Task<Void, Never>?
    private var padUpdateTask: Task<Void, Never>?
    private var backupMirrorTask: Task<Void, Never>?
    private var availableReleaseURL: URL?
    private weak var padCustomizationManager: (any PadCustomizationManaging)?

    init(
        store: WorkspaceStore,
        shortcutService: GlobalShortcutService,
        defaults: UserDefaults = .standard,
        bundledApp: Bool? = nil,
        launchAtLoginEnabled: @escaping @MainActor () -> Bool = {
            SMAppService.mainApp.status == .enabled
        },
        setLaunchAtLogin: @escaping @MainActor (Bool) throws -> Void = { enabled in
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        },
        openURL: @escaping @MainActor (URL) -> Void = { _ = NSWorkspace.shared.open($0) },
        showError: @escaping @MainActor (String, String) -> Void = { message, details in
            let alert = NSAlert()
            alert.messageText = message
            alert.informativeText = details
            alert.runModal()
        },
        convertFont: @escaping @MainActor (NSFont) -> NSFont = {
            NSFontManager.shared.convert($0)
        },
        chooseBackupMirrorDirectory: @escaping @MainActor () -> URL? = {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.message = "Choose a folder in iCloud Drive for BetterTot backups."
            panel.prompt = "Use Folder"
            return panel.runModal() == .OK ? panel.url : nil
        },
        currentVersion: String? = nil,
        currentBuild: String? = nil,
        checkForUpdates: (@MainActor () async throws -> UpdateCheckOutcome)? = nil
    ) {
        self.store = store
        self.shortcutService = shortcutService
        self.defaults = defaults
        self.bundledApp = bundledApp ?? Self.isBundledApp
        self.launchAtLoginEnabled = launchAtLoginEnabled
        self.setLaunchAtLogin = setLaunchAtLogin
        self.openURL = openURL
        self.showError = showError
        self.convertFont = convertFont
        self.chooseBackupMirrorDirectory = chooseBackupMirrorDirectory
        let resolvedVersion = currentVersion ?? Self.bundleVersion
        self.currentVersion = resolvedVersion
        self.currentBuild = currentBuild ?? Self.bundleBuild

        if let checkForUpdates {
            self.checkForUpdates = checkForUpdates
        } else if let version = AppVersion(resolvedVersion) {
            let checker = GitHubUpdateChecker.live()
            self.checkForUpdates = {
                try await checker.check(currentVersion: version)
            }
        } else {
            self.checkForUpdates = {
                throw UpdateCheckError.invalidResponse
            }
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 460),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "BetterTot Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 680, height: 460)
        window.isMovableByWindowBackground = true
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        updateTask?.cancel()
        padUpdateTask?.cancel()
        backupMirrorTask?.cancel()
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
        }
    }

    func present() {
        endRecording()
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    func connectPadCustomizationManager(_ manager: any PadCustomizationManaging) {
        padCustomizationManager = manager
        settingsView.padCustomizationView.updatePads(manager.padMetadata)
        settingsView.padCustomizationView.setEditingEnabled(true)
    }

    private func buildContent() {
        for (control, key) in editorSwitchKeys {
            control.target = self
            control.action = #selector(editorSwitchChanged(_:))
            control.identifier = NSUserInterfaceItemIdentifier(key)
        }

        settingsView.launchAtLogin.target = self
        settingsView.launchAtLogin.action = #selector(launchAtLoginChanged)
        settingsView.shortcutButton.target = self
        settingsView.shortcutButton.action = #selector(recordShortcut)
        settingsView.fontButton.target = self
        settingsView.fontButton.action = #selector(showFontPanel)
        settingsView.backupMirrorSwitch.target = self
        settingsView.backupMirrorSwitch.action = #selector(backupMirrorSwitchChanged)
        settingsView.backupMirrorButton.target = self
        settingsView.backupMirrorButton.action = #selector(chooseBackupMirrorFolder)
        settingsView.checkUpdatesButton.target = self
        settingsView.checkUpdatesButton.action = #selector(checkForUpdatesPressed)
        settingsView.viewUpdateButton.target = self
        settingsView.viewUpdateButton.action = #selector(viewUpdatePressed)
        settingsView.onNavigate = { [weak self] _ in self?.endRecording() }
        settingsView.onOpenBackupFolder = { [weak self] in self?.openBackupFolder() }
        settingsView.padCustomizationView.onUpdateRequested = {
            [weak self] id, name, colorIdentifier in
            self?.updatePadAppearance(id, name: name, colorIdentifier: colorIdentifier)
        }
        window?.contentView = settingsView
    }

    private var editorSwitchKeys: [(NSSwitch, String)] {
        [
            (settingsView.spellChecking, SettingsKeys.spellChecking),
            (settingsView.smartQuotes, SettingsKeys.smartQuotes),
            (settingsView.smartDashes, SettingsKeys.smartDashes),
            (settingsView.writingTools, SettingsKeys.writingTools),
        ]
    }

    private func refresh() {
        for (control, key) in editorSwitchKeys {
            control.state = defaults.bool(forKey: key) ? .on : .off
        }
        settingsView.shortcutButton.title =
            shortcutService.currentShortcut?.display ?? "None — click to set"

        let font = SettingsKeys.editorFont(in: defaults)
        settingsView.fontLabel.stringValue =
            "\(font.displayName ?? font.fontName) \(Int(font.pointSize)) pt"
        settingsView.currentVersionLabel.stringValue =
            "Version \(currentVersion) (\(currentBuild))"

        if bundledApp {
            settingsView.launchAtLogin.isEnabled = true
            settingsView.launchAtLogin.state = launchAtLoginEnabled() ? .on : .off
            settingsView.launchAtLogin.toolTip = nil
        } else {
            settingsView.launchAtLogin.isEnabled = false
            settingsView.launchAtLogin.toolTip =
                "Requires an app bundle — build one with scripts/bundle.sh"
        }

        if AppVersion(currentVersion) == nil {
            settingsView.checkUpdatesButton.isEnabled = false
            settingsView.updateStatus.stringValue = "Update checks require a bundled build."
        }

        if #available(macOS 15.1, *) {
            settingsView.writingTools.isEnabled = true
            settingsView.writingTools.toolTip = nil
        } else {
            settingsView.writingTools.isEnabled = false
            settingsView.writingTools.state = .off
            settingsView.writingTools.toolTip = "Requires macOS 15.1 or later"
        }

        let selectedMirror = SettingsKeys.storedBackupMirrorDirectory(in: defaults)
        settingsView.setBackupMirror(
            enabled: SettingsKeys.activeBackupMirrorDirectory(in: defaults) != nil,
            selectedDirectory: selectedMirror,
            status: nil
        )
        if let activeMirror = SettingsKeys.activeBackupMirrorDirectory(in: defaults) {
            configureBackupMirror(at: activeMirror)
        }

        if let padCustomizationManager {
            settingsView.padCustomizationView.updatePads(padCustomizationManager.padMetadata)
            settingsView.padCustomizationView.setEditingEnabled(padUpdateTask == nil)
        } else {
            settingsView.padCustomizationView.setEditingEnabled(false)
        }

        Task { @MainActor [weak self] in
            await self?.refreshBackupSummary()
        }
    }

    func refreshBackupSummary() async {
        let counts = await store.backupCounts()
        let status = await store.backupMirrorStatus()
        let selectedMirror = SettingsKeys.storedBackupMirrorDirectory(in: defaults)
        let activeMirror = SettingsKeys.activeBackupMirrorDirectory(in: defaults)
        settingsView.setBackupCounts(counts)
        if backupMirrorTask == nil {
            settingsView.setBackupMirror(
                enabled: activeMirror != nil,
                selectedDirectory: selectedMirror,
                status: status
            )
        }
    }

    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var bundleVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "Development"
    }

    static var bundleBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local"
    }

    // MARK: - Settings actions

    @objc private func editorSwitchChanged(_ sender: NSSwitch) {
        guard let key = sender.identifier?.rawValue else { return }
        defaults.set(sender.state == .on, forKey: key)
    }

    @objc private func launchAtLoginChanged() {
        do {
            try setLaunchAtLogin(settingsView.launchAtLogin.state == .on)
        } catch {
            let diagnostic = error as NSError
            NSLog(
                "BetterTot: login item change failed (%@:%ld)",
                diagnostic.domain,
                diagnostic.code
            )
            settingsView.launchAtLogin.state =
                settingsView.launchAtLogin.state == .on ? .off : .on
            showError("Could not update the login item.", error.localizedDescription)
        }
    }

    // MARK: - Shortcut recording

    @objc private func recordShortcut() {
        if recordingMonitor != nil {
            endRecording()
            return
        }
        settingsView.shortcutButton.title = "Type new shortcut… (⎋ cancels)"
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.recordingMonitor != nil else { return event }
            guard event.window === self.window else { return event }
            self.handleShortcutEvent(event)
            return nil
        }
    }

    func handleShortcutEvent(_ event: NSEvent) {
        let modifiers = Shortcut.carbonModifiers(from: event.modifierFlags)
        if event.keyCode == 53, modifiers == 0 {
            endRecording()
            return
        }
        let candidate = Shortcut.from(event: event)
        guard Shortcut.isValid(
            keyCode: candidate.keyCode,
            carbonModifiers: candidate.carbonModifiers
        ) else {
            NSSound.beep()
            return
        }
        let previous = shortcutService.currentShortcut
        do {
            try shortcutService.register(candidate)
            SettingsKeys.save(candidate, to: defaults)
            endRecording()
        } catch {
            if let previous {
                try? shortcutService.register(previous)
            }
            endRecording()
            showError("That shortcut is unavailable.", error.localizedDescription)
        }
    }

    private func endRecording() {
        if let recordingMonitor {
            NSEvent.removeMonitor(recordingMonitor)
        }
        recordingMonitor = nil
        settingsView.shortcutButton.title =
            shortcutService.currentShortcut?.display ?? "None — click to set"
    }

    // MARK: - Font and storage

    @objc private func showFontPanel() {
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(SettingsKeys.editorFont(in: defaults), isMultiple: false)
        manager.orderFrontFontPanel(self)
    }

    @objc func changeFont(_ sender: Any?) {
        let font = convertFont(SettingsKeys.editorFont(in: defaults))
        SettingsKeys.save(font, to: defaults)
        settingsView.fontLabel.stringValue =
            "\(font.displayName ?? font.fontName) \(Int(font.pointSize)) pt"
    }

    private func openBackupFolder() {
        openURL(store.backupsDirectory)
    }

    @objc private func backupMirrorSwitchChanged() {
        if settingsView.backupMirrorSwitch.state == .off {
            defaults.set(false, forKey: SettingsKeys.backupMirrorEnabled)
            configureBackupMirror(at: nil)
            return
        }
        if let directory = SettingsKeys.storedBackupMirrorDirectory(in: defaults) {
            configureBackupMirrorCandidate(at: directory)
            return
        }
        guard let directory = chooseBackupMirrorDirectory() else {
            settingsView.backupMirrorSwitch.state = .off
            return
        }
        enableBackupMirror(at: directory)
    }

    @objc private func chooseBackupMirrorFolder() {
        guard let directory = chooseBackupMirrorDirectory() else { return }
        enableBackupMirror(at: directory)
    }

    private func enableBackupMirror(at directory: URL) {
        guard directory.isFileURL, directory.path != "/" else {
            showError(
                "Could not use that backup folder.",
                "Choose a folder on this Mac or in iCloud Drive."
            )
            return
        }
        configureBackupMirrorCandidate(at: directory.standardizedFileURL)
    }

    private func configureBackupMirror(at directory: URL?) {
        guard backupMirrorTask == nil else { return }
        let selected = SettingsKeys.storedBackupMirrorDirectory(in: defaults)
        settingsView.setBackupMirror(
            enabled: directory != nil,
            selectedDirectory: selected,
            status: nil,
            busy: true
        )
        backupMirrorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let status = await store.configureBackupMirror(at: directory)
            guard !Task.isCancelled else { return }
            settingsView.setBackupMirror(
                enabled: directory != nil
                    && defaults.bool(forKey: SettingsKeys.backupMirrorEnabled),
                selectedDirectory: selected,
                status: status
            )
            backupMirrorTask = nil
        }
    }

    private func configureBackupMirrorCandidate(at directory: URL) {
        guard backupMirrorTask == nil else { return }
        let candidate = directory.standardizedFileURL
        let previous = SettingsKeys.activeBackupMirrorDirectory(in: defaults)
        settingsView.setBackupMirror(
            enabled: true,
            selectedDirectory: candidate,
            status: nil,
            busy: true
        )
        backupMirrorTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let attempted = await store.configureBackupMirror(at: candidate)
            guard !Task.isCancelled else { return }
            let configured = attempted.directory != nil
                && attempted.errorDescription == nil
            if configured {
                SettingsKeys.saveBackupMirrorDirectory(candidate, to: defaults)
                defaults.set(true, forKey: SettingsKeys.backupMirrorEnabled)
                settingsView.setBackupMirror(
                    enabled: true,
                    selectedDirectory: candidate,
                    status: attempted
                )
            } else {
                let restored = await store.configureBackupMirror(at: previous)
                settingsView.setBackupMirror(
                    enabled: previous != nil,
                    selectedDirectory: previous,
                    status: previous == nil ? attempted : restored
                )
                if previous != nil {
                    showError(
                        "Could not change the backup mirror.",
                        attempted.errorDescription ?? "The selected folder is unavailable."
                    )
                }
            }
            backupMirrorTask = nil
        }
    }

    func waitForBackupMirrorConfiguration() async {
        await backupMirrorTask?.value
    }

    private func updatePadAppearance(
        _ id: PadID,
        name: String?,
        colorIdentifier: String?
    ) {
        guard padUpdateTask == nil, let manager = padCustomizationManager else { return }
        settingsView.padCustomizationView.setEditingEnabled(false)
        padUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                _ = try await manager.updatePadAppearance(
                    id,
                    name: name,
                    colorIdentifier: colorIdentifier
                )
                guard !Task.isCancelled else { return }
                settingsView.padCustomizationView.updatePads(manager.padMetadata)
            } catch {
                guard !Task.isCancelled else { return }
                settingsView.padCustomizationView.updatePads(manager.padMetadata)
                showError("Could not update the scratchpad.", error.localizedDescription)
            }
            settingsView.padCustomizationView.setEditingEnabled(true)
            padUpdateTask = nil
        }
    }

    // MARK: - Updates

    @objc private func checkForUpdatesPressed() {
        guard updateTask == nil else { return }
        availableReleaseURL = nil
        settingsView.viewUpdateButton.isHidden = true
        setUpdateStatus("Checking for updates…", announce: true)
        settingsView.setCheckingForUpdates(true)

        let checkForUpdates = self.checkForUpdates
        updateTask = Task { @MainActor [weak self] in
            do {
                let outcome = try await checkForUpdates()
                guard !Task.isCancelled, let self else { return }
                self.render(outcome)
                self.finishUpdateCheck()
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.setUpdateStatus(
                    "Could not check for updates. \(error.localizedDescription)",
                    announce: true
                )
                self.finishUpdateCheck()
            }
        }
    }

    private func render(_ outcome: UpdateCheckOutcome) {
        switch outcome {
        case .upToDate:
            setUpdateStatus(
                "BetterTot \(currentVersion) is up to date.",
                announce: true
            )
        case .noPublishedReleases:
            setUpdateStatus("No published updates are available.", announce: true)
        case .updateAvailable(let release):
            availableReleaseURL = release.pageURL
            setUpdateStatus(
                "Version \(release.version) is available.",
                announce: true
            )
            settingsView.viewUpdateButton.isHidden = false
        }
    }

    private func setUpdateStatus(_ message: String, announce: Bool) {
        settingsView.updateStatus.stringValue = message
        settingsView.updateStatus.setAccessibilityValue(message)
        guard announce else { return }
        NSAccessibility.post(
            element: settingsView.updateStatus,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }

    private func finishUpdateCheck() {
        settingsView.setCheckingForUpdates(false)
        updateTask = nil
    }

    @objc private func viewUpdatePressed() {
        guard let availableReleaseURL else { return }
        openURL(availableReleaseURL)
    }

    // MARK: - Window lifecycle

    func windowDidResignKey(_ notification: Notification) {
        endRecording()
    }

    func windowWillClose(_ notification: Notification) {
        endRecording()
        let wasCheckingForUpdates = updateTask != nil
        updateTask?.cancel()
        updateTask = nil
        settingsView.setCheckingForUpdates(false)
        if wasCheckingForUpdates {
            availableReleaseURL = nil
            settingsView.viewUpdateButton.isHidden = true
            setUpdateStatus(Self.idleUpdateStatus, announce: false)
        }
        if NSFontManager.shared.target === self {
            NSFontManager.shared.target = nil
            NSFontPanel.shared.orderOut(nil)
        }
    }
}
