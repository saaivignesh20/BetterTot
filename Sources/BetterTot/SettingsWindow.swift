import AppKit
import ServiceManagement

enum SettingsKeys {
    static let spellChecking = "spellChecking"
    static let smartQuotes = "smartQuotes"
    static let smartDashes = "smartDashes"
    static let fontName = "editorFontName"
    static let fontSize = "editorFontSize"
    static let globalShortcut = "globalShortcut"

    static func loadShortcut(from defaults: UserDefaults = .standard) -> Shortcut {
        guard let data = defaults.data(forKey: globalShortcut),
              let shortcut = try? JSONDecoder().decode(Shortcut.self, from: data),
              // Re-validate at the trust boundary: a hand-edited or migrated
              // plist must never register a bare key that eats ordinary typing.
              Shortcut.isValid(keyCode: shortcut.keyCode,
                               carbonModifiers: shortcut.carbonModifiers) else {
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

    static let defaults: [String: Any] = [
        spellChecking: true,
        smartQuotes: false,
        smartDashes: false,
        fontSize: 14.0,
    ]

    static var editorFont: NSFont {
        editorFont(in: .standard)
    }

    static func editorFont(in defaults: UserDefaults) -> NSFont {
        let size = defaults.double(forKey: fontSize)
        if let name = defaults.string(forKey: fontName), let font = NSFont(name: name, size: size) {
            return font
        }
        return .systemFont(ofSize: size)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let store: WorkspaceStore
    private let shortcutService: GlobalShortcutService
    private let defaults: UserDefaults
    private let bundledApp: Bool
    private let launchAtLoginEnabled: @MainActor () -> Bool
    private let setLaunchAtLogin: @MainActor (Bool) throws -> Void
    private let openURL: @MainActor (URL) -> Void
    private let showError: @MainActor (String, String) -> Void
    private let convertFont: @MainActor (NSFont) -> NSFont
    private let launchAtLogin = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let spellChecking = NSButton(checkboxWithTitle: "Check spelling while typing", target: nil, action: nil)
    private let smartQuotes = NSButton(checkboxWithTitle: "Smart quotes", target: nil, action: nil)
    private let smartDashes = NSButton(checkboxWithTitle: "Smart dashes", target: nil, action: nil)
    private let shortcutButton = NSButton(title: "", target: nil, action: nil)
    private let fontLabel = NSTextField(labelWithString: "")
    private let backupSummary = NSTextField(labelWithString: "Backups: …")
    private var recordingMonitor: Any?

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
        convertFont: @escaping @MainActor (NSFont) -> NSFont = { NSFontManager.shared.convert($0) }
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "BetterTot Settings"
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func present() {
        endRecording() // re-presenting must never leave an invisible recording session
        refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        for (button, key) in checkboxKeys {
            button.target = self
            button.action = #selector(checkboxChanged(_:))
            button.identifier = NSUserInterfaceItemIdentifier(key)
        }
        launchAtLogin.target = self
        launchAtLogin.action = #selector(launchAtLoginChanged)

        shortcutButton.target = self
        shortcutButton.action = #selector(recordShortcut)
        shortcutButton.setAccessibilityLabel("Global shortcut")
        let shortcutRow = NSStackView(views: [
            NSTextField(labelWithString: "Global shortcut:"), shortcutButton,
        ])
        shortcutRow.orientation = .horizontal

        let fontButton = NSButton(title: "Change Font…", target: self, action: #selector(showFontPanel))
        let fontRow = NSStackView(views: [fontButton, fontLabel])
        fontRow.orientation = .horizontal

        let openBackups = NSButton(title: "Open Backup Folder", target: self, action: #selector(openBackupFolder))
        backupSummary.textColor = .secondaryLabelColor
        backupSummary.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let stack = NSStackView(views: [
            sectionLabel("General"),
            launchAtLogin,
            shortcutRow,
            sectionLabel("Editor"),
            spellChecking,
            smartQuotes,
            smartDashes,
            fontRow,
            sectionLabel("Backups"),
            openBackups,
            backupSummary,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.setCustomSpacing(16, after: shortcutRow)
        stack.setCustomSpacing(16, after: fontRow)
        window?.contentView = stack
    }

    private var checkboxKeys: [(NSButton, String)] {
        [
            (spellChecking, SettingsKeys.spellChecking),
            (smartQuotes, SettingsKeys.smartQuotes),
            (smartDashes, SettingsKeys.smartDashes),
        ]
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    private func refresh() {
        for (button, key) in checkboxKeys {
            button.state = defaults.bool(forKey: key) ? .on : .off
        }
        shortcutButton.title = shortcutService.currentShortcut?.display ?? "None — click to set"
        let font = SettingsKeys.editorFont(in: defaults)
        fontLabel.stringValue = "\(font.displayName ?? font.fontName) \(Int(font.pointSize))"

        if bundledApp {
            launchAtLogin.isEnabled = true
            launchAtLogin.state = launchAtLoginEnabled() ? .on : .off
        } else {
            launchAtLogin.isEnabled = false
            launchAtLogin.toolTip = "Requires an app bundle — build one with scripts/bundle.sh"
        }

        Task { @MainActor [weak self] in await self?.refreshBackupSummary() }
    }

    func refreshBackupSummary() async {
        let counts = await store.backupCounts()
        backupSummary.stringValue = BackupKind.allCases
            .map { kind in
                let kept = kind.retention.map { " (keeps \($0))" } ?? ""
                return "\(kind.rawValue.capitalized): \(counts[kind] ?? 0)\(kept)"
            }
            .joined(separator: " · ")
    }

    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    // MARK: - Actions

    @objc private func checkboxChanged(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue else { return }
        defaults.set(sender.state == .on, forKey: key)
    }

    @objc private func launchAtLoginChanged() {
        do {
            try setLaunchAtLogin(launchAtLogin.state == .on)
        } catch {
            let diagnostic = error as NSError
            NSLog("BetterTot: login item change failed (%@:%ld)",
                  diagnostic.domain, diagnostic.code)
            launchAtLogin.state = launchAtLogin.state == .on ? .off : .on // revert
            showError("Could not update the login item.", error.localizedDescription)
        }
    }

    // MARK: - Shortcut recording

    @objc private func recordShortcut() {
        if recordingMonitor != nil {
            endRecording()
            return
        }
        shortcutButton.title = "Type new shortcut… (⎋ cancels)"
        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recordingMonitor != nil else { return event }
            // Only keys aimed at this window are shortcut candidates. Without
            // this, recording would swallow typing in the pinned scratchpad
            // and silently rebind the global shortcut to ⌘V and friends.
            guard event.window === self.window else { return event }
            self.handleShortcutEvent(event)
            return nil // recording swallows the event
        }
    }

    func handleShortcutEvent(_ event: NSEvent) {
        let modifiers = Shortcut.carbonModifiers(from: event.modifierFlags)
        if event.keyCode == 53, modifiers == 0 { // bare Escape cancels
            endRecording()
            return
        }
        let candidate = Shortcut.from(event: event)
        guard Shortcut.isValid(keyCode: candidate.keyCode, carbonModifiers: candidate.carbonModifiers) else {
            NSSound.beep() // needs ⌘/⌥/⌃ (or an F-key); keep listening
            return
        }
        let previous = shortcutService.currentShortcut
        do {
            try shortcutService.register(candidate)
            SettingsKeys.save(candidate, to: defaults)
            endRecording()
        } catch {
            // Actionable conflict handling (plan §4.2): restore the old
            // shortcut and tell the user why the new one was rejected.
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
        shortcutButton.title = shortcutService.currentShortcut?.display ?? "None — click to set"
    }

    @objc private func showFontPanel() {
        let manager = NSFontManager.shared
        manager.target = self
        manager.setSelectedFont(SettingsKeys.editorFont(in: defaults), isMultiple: false)
        manager.orderFrontFontPanel(self)
    }

    @objc func changeFont(_ sender: Any?) {
        let font = convertFont(SettingsKeys.editorFont(in: defaults))
        SettingsKeys.save(font, to: defaults)
        fontLabel.stringValue = "\(font.displayName ?? font.fontName) \(Int(font.pointSize))"
    }

    @objc private func openBackupFolder() {
        openURL(store.backupsDirectory)
    }

    // Clicking away (e.g. the panel taking key) ends recording rather than
    // leaving an invisible session armed.
    func windowDidResignKey(_ notification: Notification) {
        endRecording()
    }

    func windowWillClose(_ notification: Notification) {
        endRecording()
        if NSFontManager.shared.target === self {
            NSFontManager.shared.target = nil
            NSFontPanel.shared.orderOut(nil)
        }
    }
}
