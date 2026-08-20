import AppKit

enum PanelDismissalReason {
    case escape
    case outsideClick
    case statusItemToggle
    case globalShortcutToggle
    case explicitClose
    case termination
}

enum PadCommand {
    case select(Int)
    case previous
    case next
    case copyAll
    case clear
}

enum FlushResult: Equatable {
    case committed
    case journaled
    case failed
}

private struct PersistenceRevision: Hashable {
    let padID: PadID
    let revision: UInt64
}

private struct LocatedAutomaticListLine {
    let range: NSRange
    let text: NSString
    let list: AutomaticListLine
}

final class ScratchpadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var onTogglePin: (() -> Void)?
    var onPadCommand: ((PadCommand) -> Void)?
    var canSwitchPads: (() -> Bool)?
    var onToggleCheckbox: (() -> Bool)?
    var onOpenSettings: (() -> Void)?
    var onClose: (() -> Void)?

    // ponytail: accessory app has no menu bar, so standard edit key equivalents
    // are routed by hand here; replace with a real main menu when settings land.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let shortcutModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        let modifiers = event.modifierFlags.intersection(shortcutModifiers)
        if event.keyCode == 36,
           modifiers == .command,
           onToggleCheckbox?() == true {
            return true
        }
        if event.keyCode == 48, canSwitchPads?() != false {
            if modifiers == [.control, .shift] {
                onPadCommand?(.previous)
                return true
            }
            if modifiers == .control {
                onPadCommand?(.next)
                return true
            }
        }
        if super.performKeyEquivalent(with: event) { return true }
        guard event.modifierFlags.contains(.command) else { return false }
        let shift = event.modifierFlags.contains(.shift)
        let option = event.modifierFlags.contains(.option)
        let control = event.modifierFlags.contains(.control)

        switch event.keyCode {
        case 51 where shift && !option && !control: onPadCommand?(.clear); return true // ⇧⌘⌫
        default: break
        }

        guard let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        if let number = Int(key), (1...WorkspaceMetadata.padCount).contains(number) {
            onPadCommand?(.select(number - 1))
            return true
        }
        switch key {
        case "x": return NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case "c" where shift: onPadCommand?(.copyAll); return true
        case "c": return NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case "v": return NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case "a": return NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
        case "z":
            let action = shift ? Selector(("redo:")) : Selector(("undo:"))
            return NSApp.sendAction(action, to: nil, from: self)
        case "p": onTogglePin?(); return true
        case ",": onOpenSettings?(); return true
        case "w" where !shift && !option && !control:
            onClose?()
            return true
        case "q": NSApp.terminate(nil); return true
        default: return false
        }
    }
}

@MainActor
final class PanelController: NSObject, NSTextViewDelegate, NSWindowDelegate,
    SettingsWorkspaceManaging {
    private let statusItem: NSStatusItem
    let store: WorkspaceStore
    private let defaults: UserDefaults
    private let panel: ScratchpadPanel
    let textView: NSTextView
    private let scrollView: NSScrollView
    private let content: PanelContentView

    private var pads: [PadMetadata]
    private var selectedIndex: Int
    private var texts: [PadID: String]
    private var revisions: [PadID: UInt64] = [:]
    private var undoManagers: [PadID: UndoManager] = [:]
    private var saveStates: [PadID: PanelSaveState] = [:]
    private var journalTasks: [PersistenceRevision: Task<Bool, Never>] = [:]
    private var commitTasks: [PersistenceRevision: Task<Void, Never>] = [:]
    private var padStateTasks: [Task<Void, Never>] = []

    private var isPinned = false
    private var attachedOrigin: NSPoint?
    private var pendingSave: DispatchWorkItem?
    private var mouseMonitors: [Any] = []
    private var editingSuspensionCount = 0
    private var isWritingToolsSessionActive = false
    private var editableBeforeSuspension = true
    var onOpenSettings: (() -> Void)?
    private var checkboxEditor: CheckboxTextView {
        textView as! CheckboxTextView
    }
    var currentSourceText: String { checkboxEditor.sourceText }
    var currentPlainText: String { checkboxEditor.plainText }
    var currentVisibleText: String { checkboxEditor.visibleText }
    var padMetadata: [PadMetadata] { pads }

    init(
        statusItem: NSStatusItem,
        store: WorkspaceStore,
        snapshot: WorkspaceSnapshot,
        defaults: UserDefaults = .standard
    ) {
        self.statusItem = statusItem
        self.store = store
        self.defaults = defaults
        self.pads = snapshot.metadata.pads.sorted { $0.position < $1.position }
        self.texts = snapshot.texts
        self.selectedIndex = pads.firstIndex { $0.id == snapshot.metadata.selectedPadID } ?? 0
        self.revisions = snapshot.revisions

        let editor = CheckboxTextView.makeScrollable()
        scrollView = editor.scrollView
        textView = editor.textView
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.drawsBackground = false
        textView.textColor = .labelColor
        scrollView.drawsBackground = false

        content = PanelContentView(
            scrollView: scrollView,
            pads: pads,
            selectedIndex: selectedIndex
        )

        panel = ScratchpadPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = content
        panel.isMovableByWindowBackground = true
        content.layoutSubtreeIfNeeded()
        editor.textView.fitDocument(to: scrollView)

        super.init()

        panel.delegate = self
        content.onClose = { [weak self] in self?.dismiss(reason: .explicitClose) }
        content.onSelectPad = { [weak self] index in
            guard let self else { return }
            self.switchToPad(at: index)
            self.panel.makeFirstResponder(self.textView)
        }
        content.onTogglePin = { [weak self] in self?.togglePin() }
        content.onOpenSettings = { [weak self] in self?.openSettings() }
        content.onToggleBulletedList = { [weak self] in self?.toggleList(.bulleted) }
        content.onToggleNumberedList = { [weak self] in self?.toggleList(.numbered) }
        content.onToggleCheckboxList = { [weak self] in self?.toggleList(.checkbox) }
        textView.delegate = self
        editor.textView.onCheckboxActivation = { [weak self] location in
            _ = self?.toggleCheckbox(atUTF16Location: location, markerHitOnly: true)
        }
        panel.onTogglePin = { [weak self] in self?.togglePin() }
        panel.onPadCommand = { [weak self] command in self?.handle(command) }
        panel.canSwitchPads = { [weak self] in
            guard let self else { return false }
            return !self.textView.hasMarkedText() && !self.writingToolsInteractionIsActive
        }
        panel.onToggleCheckbox = { [weak self] in self?.toggleCurrentCheckbox() ?? false }
        panel.onOpenSettings = { [weak self] in self?.openSettings() }
        panel.onClose = { [weak self] in self?.dismiss(reason: .explicitClose) }
        applySettings()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: defaults
        )
        loadSelectedPadIntoEditor()
    }

    deinit {
        pendingSave?.cancel()
        journalTasks.values.forEach { $0.cancel() }
        commitTasks.values.forEach { $0.cancel() }
        padStateTasks.forEach { $0.cancel() }
        mouseMonitors.forEach(NSEvent.removeMonitor)
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Settings

    @objc private func defaultsChanged() {
        applySettings()
    }

    func applySettings() {
        let font = SettingsKeys.editorFont(in: defaults)
        textView.font = font
        if let checkboxTextView = textView as? CheckboxTextView {
            checkboxTextView.updateCheckboxPresentation(
                baseFont: font,
                tintColor: PanelContentView.padColor(for: pads[selectedIndex])
            )
        }
        textView.isContinuousSpellCheckingEnabled = defaults.bool(forKey: SettingsKeys.spellChecking)
        textView.isAutomaticQuoteSubstitutionEnabled = defaults.bool(forKey: SettingsKeys.smartQuotes)
        textView.isAutomaticDashSubstitutionEnabled = defaults.bool(forKey: SettingsKeys.smartDashes)
        if #available(macOS 15.1, *) {
            textView.writingToolsBehavior = defaults.bool(forKey: SettingsKeys.writingTools)
                ? .default
                : .none
        } else if #available(macOS 15.0, *) {
            textView.writingToolsBehavior = .none
        }
    }

    @discardableResult
    func updatePadAppearance(
        _ id: PadID,
        name: String?,
        colorIdentifier: String?
    ) async throws -> PadMetadata {
        let persisted = try await store.updatePadAppearance(
            id,
            name: name,
            colorIdentifier: colorIdentifier
        )
        guard let index = pads.firstIndex(where: { $0.id == id }) else {
            throw PadCustomizationError.unknownPad
        }

        var updatedPad = pads[index]
        updatedPad.name = persisted.name
        updatedPad.colorIdentifier = persisted.colorIdentifier
        updatedPad.updatedAt = persisted.updatedAt
        var updatedPads = pads
        updatedPads[index] = updatedPad
        pads = updatedPads
        content.updatePads(updatedPads)

        if index == selectedIndex {
            textView.setAccessibilityLabel(updatedPad.accessibilityName)
            checkboxEditor.updateCheckboxPresentation(
                baseFont: SettingsKeys.editorFont(in: defaults),
                tintColor: PanelContentView.padColor(for: updatedPad)
            )
        }
        return updatedPad
    }

    @objc private func openSettings() {
        guard !writingToolsInteractionIsActive else { return }
        if !isPinned {
            dismiss(reason: .explicitClose)
        }
        onOpenSettings?()
    }

    // MARK: - Pad commands

    private func handle(_ command: PadCommand) {
        switch command {
        case .select(let index):
            switchToPad(at: index)
        case .previous:
            switchToPad(at: (selectedIndex + pads.count - 1) % pads.count)
        case .next:
            switchToPad(at: (selectedIndex + 1) % pads.count)
        case .copyAll:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(currentSourceText, forType: .string)
        case .clear:
            clearCurrentPad()
        }
    }

    private func switchToPad(at index: Int) {
        guard !writingToolsInteractionIsActive, !textView.hasMarkedText() else {
            content.updateSelection(index: selectedIndex)
            return
        }
        guard pads.indices.contains(index), index != selectedIndex else {
            content.updateSelection(index: selectedIndex)
            return
        }
        persistCurrentPadUIState()
        commitCurrentPadNow()
        selectedIndex = index
        content.updateSelection(index: index)
        loadSelectedPadIntoEditor()
        announceSelectedPad()
        let id = pads[index].id
        let task = Task { [store] in
            guard !Task.isCancelled else { return }
            await store.select(id)
        }
        padStateTasks.append(task)
    }

    // VoiceOver hears pad changes (plan §12: proper announcements, and state
    // never conveyed by color alone).
    private func announceSelectedPad() {
        let pad = pads[selectedIndex]
        let suffix = (texts[pad.id] ?? "").isEmpty ? ", empty" : ""
        NSAccessibility.post(
            element: panel,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "\(pad.accessibilityName)\(suffix)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func loadSelectedPadIntoEditor() {
        let pad = pads[selectedIndex]
        let storedText = texts[pad.id] ?? ""
        textView.setAccessibilityLabel(pad.accessibilityName)
        let projection = checkboxEditor.setSourceText(
            storedText,
            baseFont: SettingsKeys.editorFont(in: defaults),
            tintColor: PanelContentView.padColor(for: pad)
        )
        content.updateTextStatistics(checkboxEditor.visibleText)
        content.updateSaveState(saveStates[pad.id] ?? .saved)
        let sourceSelection = NSRange(
            location: pad.selection.utf16Location,
            length: pad.selection.utf16Length
        )
        let displaySelection = projection.inputToDisplayMap
            .displayRange(forSourceRange: sourceSelection)
        let displayLength = textView.attributedString().length
        let displayLocation = min(max(0, displaySelection.location), displayLength)
        textView.setSelectedRange(NSRange(
            location: displayLocation,
            length: min(displaySelection.length, displayLength - displayLocation)
        ))
        if projection.canonicalSource != storedText {
            let canonicalRange = checkboxEditor.sourceRange(
                forDisplayRange: textView.selectedRange()
            )
            let canonicalSelection = StoredSelection(
                utf16Location: canonicalRange.location,
                utf16Length: canonicalRange.length
            )
            pads[selectedIndex].selection = canonicalSelection
            let task = Task { [store] in
                await store.updatePadState(
                    pad.id,
                    selection: canonicalSelection,
                    scrollOffset: pad.scrollOffset
                )
            }
            padStateTasks.append(task)
            textView.didChangeText()
        }
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let maxOffset = max(0, textView.frame.height - scrollView.contentView.bounds.height)
        let offset = min(max(0, pad.scrollOffset), maxOffset)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func persistCurrentPadUIState() {
        let range = checkboxEditor.sourceRange(forDisplayRange: textView.selectedRange())
        let selection = StoredSelection(utf16Location: range.location, utf16Length: range.length)
        let offset = Double(scrollView.contentView.bounds.origin.y)
        pads[selectedIndex].selection = selection
        pads[selectedIndex].scrollOffset = offset
        let id = pads[selectedIndex].id
        let task = Task { [store] in
            guard !Task.isCancelled else { return }
            await store.updatePadState(id, selection: selection, scrollOffset: offset)
        }
        padStateTasks.append(task)
    }

    // Undoable clear (plan §4.3: clearing needs confirmation or immediate undo).
    private func clearCurrentPad() {
        guard !writingToolsInteractionIsActive else { return }
        let full = NSRange(location: 0, length: textView.attributedString().length)
        guard full.length > 0, textView.shouldChangeText(in: full, replacementString: "") else { return }
        textView.textStorage?.replaceCharacters(in: full, with: "")
        textView.didChangeText()
    }

    // Per-pad undo stacks so undo after a switch never edits the wrong pad.
    func undoManager(for view: NSTextView) -> UndoManager? {
        let id = pads[selectedIndex].id
        if let manager = undoManagers[id] { return manager }
        let manager = UndoManager()
        undoManagers[id] = manager
        return manager
    }

    // MARK: - Show / dismiss (the only dismissal paths, plan §5.3)

    func toggle(reason: PanelDismissalReason) {
        if panel.isVisible {
            if isPinned {
                panel.makeKeyAndOrderFront(nil)
                panel.makeFirstResponder(textView)
            } else {
                dismiss(reason: reason)
            }
        } else {
            show()
        }
    }

    func show() {
        if !isPinned {
            positionPanel()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
        if !isPinned { installMouseMonitors() }
    }

    func dismiss(reason: PanelDismissalReason) {
        if isPinned {
            switch reason {
            case .explicitClose:
                isPinned = false
                content.updatePinned(false)
            case .termination:
                break
            case .escape, .outsideClick, .statusItemToggle, .globalShortcutToggle:
                return
            }
        }
        persistCurrentPadUIState()
        commitCurrentPadNow()
        removeMouseMonitors()
        panel.orderOut(nil)
    }

    private func togglePin() {
        setPinned(!isPinned)
    }

    private func setPinned(_ pinned: Bool) {
        guard isPinned != pinned else { return }
        isPinned = pinned
        content.updatePinned(pinned)
        if pinned {
            removeMouseMonitors()
        } else if panel.isVisible {
            positionPanel()
            installMouseMonitors()
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard notification.object as? NSWindow === panel,
              panel.isVisible,
              !isPinned,
              let attachedOrigin else {
            return
        }
        let dx = panel.frame.origin.x - attachedOrigin.x
        let dy = panel.frame.origin.y - attachedOrigin.y
        if hypot(dx, dy) >= 4 {
            setPinned(true)
        }
    }

    // MARK: - Positioning (anchored under the status item, clamped to screen)

    private func positionPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let anchor = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var origin = NSPoint(
            x: anchor.midX - panel.frame.width / 2,
            y: anchor.minY - panel.frame.height - 6
        )
        if let screen = buttonWindow.screen {
            let visible = screen.visibleFrame
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
            origin.y = max(origin.y, visible.minY + 8)
        }
        attachedOrigin = origin
        panel.setFrameOrigin(origin)
    }

    // MARK: - Outside-click monitors (installed only while an unpinned panel is visible)

    private func installMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.handleOutsideClick(
                window: event.window,
                screenLocation: NSEvent.mouseLocation,
                ownerBundleIdentifier: Self.targetBundleIdentifier(for: event))
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            guard let self else { return event }
            self.handleOutsideClick(
                window: event.window,
                screenLocation: Self.screenLocation(for: event))
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    func handleOutsideClick(
        window: NSWindow?,
        screenLocation: NSPoint,
        ownerBundleIdentifier: String? = nil
    ) {
        guard !belongsToPanel(window),
              !Self.isTextInputService(ownerBundleIdentifier),
              statusItemScreenFrame?.contains(screenLocation) != true else {
            return
        }
        dismiss(reason: .outsideClick)
    }

    private func belongsToPanel(_ window: NSWindow?) -> Bool {
        var candidate = window
        while let current = candidate {
            if current === panel { return true }
            candidate = current.parent
        }
        return false
    }

    private static func targetBundleIdentifier(for event: NSEvent) -> String? {
        guard let cgEvent = event.cgEvent else { return nil }
        let processIdentifier = pid_t(
            cgEvent.getIntegerValueField(.eventTargetUnixProcessID))
        guard processIdentifier > 0 else { return nil }
        return NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
    }

    private static func isTextInputService(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.apple.TextInputMenuAgent"
            || bundleIdentifier?.hasPrefix("com.apple.inputmethod.") == true
    }

    private var statusItemScreenFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private static func screenLocation(for event: NSEvent) -> NSPoint {
        guard let window = event.window else { return event.locationInWindow }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private func removeMouseMonitors() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
    }

    // MARK: - Persistence (journal per change, 200 ms debounced commit)

    func textDidChange(_ notification: Notification) {
        if writingToolsInteractionIsActive {
            content.updateTextStatistics(currentVisibleText)
            return
        }
        recordCurrentEditorChange()
    }

    func textView(
        _ textView: NSTextView,
        willChangeSelectionFromCharacterRange oldSelectedCharRange: NSRange,
        toCharacterRange newSelectedCharRange: NSRange
    ) -> NSRange {
        guard textView === self.textView else { return newSelectedCharRange }
        return checkboxEditor.selectionRangeBySkippingHiddenSyntax(
            newSelectedCharRange,
            from: oldSelectedCharRange
        )
    }

    @available(macOS 15.0, *)
    func textViewWritingToolsWillBegin(_ textView: NSTextView) {
        guard textView === self.textView else { return }
        commitCurrentPadNow()
        isWritingToolsSessionActive = true
    }

    @available(macOS 15.0, *)
    func textViewWritingToolsDidEnd(_ textView: NSTextView) {
        guard textView === self.textView else { return }
        isWritingToolsSessionActive = false
        recordCurrentEditorChange()
    }

    private var systemWritingToolsAreActive: Bool {
        if #available(macOS 15.0, *) {
            return textView.isWritingToolsActive
        }
        return false
    }

    private var writingToolsInteractionIsActive: Bool {
        isWritingToolsSessionActive || systemWritingToolsAreActive
    }

    private func recordCurrentEditorChange() {
        let id = pads[selectedIndex].id
        let text = currentSourceText
        texts[id] = text
        let revision = (revisions[id] ?? 0) + 1
        revisions[id] = revision
        saveStates[id] = .saving
        content.updateTextStatistics(currentVisibleText)
        content.updateSaveState(.saving)
        let key = PersistenceRevision(padID: id, revision: revision)
        let journalTask = Task { [store] in
            guard !Task.isCancelled else { return false }
            return await store.journal(id, text: text, revision: revision)
        }
        journalTasks[key] = journalTask

        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commit(id) }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func commit(_ id: PadID) {
        guard let text = texts[id], let revision = revisions[id] else { return }
        let key = PersistenceRevision(padID: id, revision: revision)
        guard commitTasks[key] == nil else { return }
        let pendingJournal = journalTasks[key]
        let task = Task { [weak self, store] in
            let journaled: Bool
            if let pendingJournal {
                journaled = await pendingJournal.value
            } else {
                journaled = false
            }
            guard !Task.isCancelled else { return }
            let committed = await store.commit(id, text: text, revision: revision)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            finishCommit(
                key: key,
                state: .resolve(committed: committed, journaled: journaled)
            )
        }
        commitTasks[key] = task
    }

    private func finishCommit(key: PersistenceRevision, state: PanelSaveState) {
        commitTasks[key] = nil
        journalTasks[key] = nil
        guard revisions[key.padID] == key.revision else { return }
        saveStates[key.padID] = state
        if pads[selectedIndex].id == key.padID {
            content.updateSaveState(state)
            if state == .failed {
                NSAccessibility.post(
                    element: panel,
                    notification: .announcementRequested,
                    userInfo: [
                        .announcement: "Scratchpad could not be saved",
                        .priority: NSAccessibilityPriorityLevel.high.rawValue,
                    ]
                )
            }
        }
    }

    private func drainPersistenceTasks() async {
        let stateTasks = padStateTasks
        padStateTasks = []
        for task in stateTasks {
            await task.value
        }

        let journals = journalTasks
        for task in journals.values {
            _ = await task.value
        }

        let commits = commitTasks
        for task in commits.values {
            await task.value
        }
        for key in journals.keys {
            journalTasks[key] = nil
        }
        for key in commits.keys {
            commitTasks[key] = nil
        }
    }

    func commitCurrentPadNow() {
        pendingSave?.cancel()
        pendingSave = nil
        commit(pads[selectedIndex].id)
    }

    func commitAllPadsAndWait() async -> Bool {
        await persistAllPads() == .committed
    }

    private func persistAllPads() async -> FlushResult {
        pendingSave?.cancel()
        pendingSave = nil
        await drainPersistenceTasks()
        await canonicalizeStoredPads()
        var allCommitted = true
        var allDurable = true
        for pad in pads {
            if let text = texts[pad.id], let revision = revisions[pad.id] {
                let journaled = await store.journal(pad.id, text: text, revision: revision)
                let committed = await store.commit(pad.id, text: text, revision: revision)
                allCommitted = committed && allCommitted
                allDurable = (journaled || committed) && allDurable
            }
        }
        if allCommitted { return .committed }
        return allDurable ? .journaled : .failed
    }

    private func canonicalizeStoredPads() async {
        for index in pads.indices {
            let id = pads[index].id
            let storedText = texts[id] ?? ""
            let storedSelection = pads[index].selection
            let result = CheckboxTextView.canonicalize(
                storedText,
                sourceRange: NSRange(
                    location: storedSelection.utf16Location,
                    length: storedSelection.utf16Length
                )
            )
            let canonicalSelection = StoredSelection(
                utf16Location: result.sourceRange.location,
                utf16Length: result.sourceRange.length
            )
            if result.source != storedText {
                texts[id] = result.source
                revisions[id] = (revisions[id] ?? 0) + 1
            }
            if canonicalSelection != storedSelection {
                pads[index].selection = canonicalSelection
                await store.updatePadState(
                    id,
                    selection: canonicalSelection,
                    scrollOffset: pads[index].scrollOffset
                )
            }
        }
    }

    func withEditingSuspended<T>(
        _ operation: @MainActor () async throws -> T
    ) async rethrows -> T {
        if editingSuspensionCount == 0 {
            editableBeforeSuspension = textView.isEditable
            textView.isEditable = false
        }
        editingSuspensionCount += 1
        defer {
            editingSuspensionCount -= 1
            if editingSuspensionCount == 0 {
                textView.isEditable = editableBeforeSuspension
            }
        }
        return try await operation()
    }

    // MARK: - Import / restore support

    var currentPadPosition: Int { pads[selectedIndex].position }

    func selectPad(at index: Int) {
        switchToPad(at: index)
    }

    // Routes through shouldChangeText/didChangeText so imports are undoable
    // and flow through the normal journal + commit path.
    func applyToCurrentPad(_ text: String, replacing: Bool) {
        let length = textView.attributedString().length
        let range: NSRange
        var insert = text
        if replacing {
            range = NSRange(location: 0, length: length)
        } else {
            range = NSRange(location: length, length: 0)
            if length > 0, !currentPlainText.hasSuffix("\n") {
                insert = "\n" + insert
            }
        }
        let replacement = checkboxEditor.attributedPresentation(for: insert)
        guard textView.shouldChangeText(in: range, replacementString: replacement.string) else {
            return
        }
        textView.textStorage?.replaceCharacters(in: range, with: replacement)
        textView.didChangeText()
    }

    // Restore pads by position from "Pad N.txt" files; missing files leave
    // the pad untouched. Returns positions whose file exists but could not be
    // read, so the caller can tell the user the workspace is a mix. Undo
    // stacks are dropped — their stored ranges would replay against foreign text.
    @discardableResult
    func restore(from padFiles: [URL]) async -> [Int]? {
        var unreadable: [Int] = []
        for (index, file) in padFiles.enumerated() where pads.indices.contains(index) {
            guard let text = Self.readTextFile(file) else {
                if FileManager.default.fileExists(atPath: file.path) {
                    unreadable.append(index)
                }
                continue
            }
            let id = pads[index].id
            texts[id] = text
            revisions[id] = (revisions[id] ?? 0) + 1
        }
        undoManagers = [:]
        loadSelectedPadIntoEditor()
        return await commitAllPadsAndWait() ? unreadable : nil
    }

    // Awaited flush for orderly termination (plan §14.3).
    @discardableResult
    func flushAll() async -> FlushResult {
        // No edit may be acknowledged after the flush snapshot is taken.
        let wasEditable = textView.isEditable
        textView.isEditable = false
        persistCurrentPadUIState()
        pendingSave?.cancel()
        pendingSave = nil
        let result = await persistAllPads()
        if result == .failed {
            textView.isEditable = wasEditable
        }
        return result
    }

    // MARK: - Editor commands

    private func toggleList(_ style: EditorListStyle) {
        guard textView.isEditable,
              !textView.hasMarkedText(),
              !writingToolsInteractionIsActive else { return }
        let result = ListFormatter.toggle(
            in: currentPlainText,
            selection: textView.selectedRange(),
            style: style
        )
        let replacement = checkboxEditor.attributedPresentation(for: result.replacement)
        guard textView.shouldChangeText(
            in: result.replacementRange,
            replacementString: replacement.string
        ) else { return }

        textView.textStorage?.replaceCharacters(in: result.replacementRange, with: replacement)
        textView.didChangeText()
        textView.setSelectedRange(result.selection)
        panel.makeFirstResponder(textView)
    }

    private func automaticListLine(
        atUTF16Location location: Int,
        in source: NSString
    ) -> LocatedAutomaticListLine? {
        guard location != NSNotFound, location <= source.length else { return nil }
        let range = source.lineRange(for: NSRange(location: location, length: 0))
        let rawLine = source.substring(with: range) as NSString
        var contentLength = rawLine.length
        while contentLength > 0, [0x0A, 0x0D].contains(rawLine.character(at: contentLength - 1)) {
            contentLength -= 1
        }
        let line = rawLine.substring(to: contentLength) as NSString
        guard let list = AutomaticListLine.parse(line) else { return nil }
        return LocatedAutomaticListLine(
            range: NSRange(location: range.location, length: contentLength),
            text: line,
            list: list
        )
    }

    @discardableResult
    private func toggleCheckbox(atUTF16Location location: Int, markerHitOnly: Bool = false) -> Bool {
        guard !writingToolsInteractionIsActive else { return false }
        let source = currentPlainText as NSString
        guard let located = automaticListLine(atUTF16Location: location, in: source),
              let replacement = located.list.toggledMarker else { return false }

        let markerRange = NSRange(
            location: located.range.location + located.list.indentationLength,
            length: located.list.markerLength
        )
        if markerHitOnly {
            let clickableRange = NSRange(
                location: markerRange.location,
                length: located.list.clickableMarkerLength
            )
            guard clickableRange.length > 0, NSLocationInRange(location, clickableRange) else {
                return false
            }
        }

        let oldSelection = textView.selectedRange()
        let attributedReplacement = checkboxEditor.attributedPresentation(for: replacement)
        guard textView.shouldChangeText(
            in: markerRange,
            replacementString: attributedReplacement.string
        ) else {
            return true
        }
        textView.textStorage?.replaceCharacters(in: markerRange, with: attributedReplacement)
        textView.didChangeText()

        let replacementLength = attributedReplacement.length
        let newLocation: Int
        if markerHitOnly {
            let lengthDelta = replacementLength - markerRange.length
            let adjustedLocation = oldSelection.location >= NSMaxRange(markerRange)
                ? oldSelection.location + lengthDelta
                : oldSelection.location
            let textLength = textView.attributedString().length
            textView.setSelectedRange(NSRange(
                location: min(max(0, adjustedLocation), textLength),
                length: min(oldSelection.length, max(0, textLength - adjustedLocation))
            ))
            return true
        } else if oldSelection.location < NSMaxRange(markerRange) {
            newLocation = markerRange.location + replacementLength
        } else {
            newLocation = oldSelection.location + replacementLength - markerRange.length
        }
        textView.setSelectedRange(NSRange(location: newLocation, length: 0))
        return true
    }

    private func toggleCurrentCheckbox() -> Bool {
        let selection = textView.selectedRange()
        guard !textView.hasMarkedText(), selection.length == 0 else { return false }
        return toggleCheckbox(atUTF16Location: selection.location)
    }

    private func handleAutomaticListReturn(in textView: NSTextView) -> Bool {
        let selection = textView.selectedRange()
        let source = currentPlainText as NSString
        guard selection.location != NSNotFound,
              selection.length == 0,
              let located = automaticListLine(
                atUTF16Location: selection.location,
                in: source
              ) else { return false }
        let list = located.list

        let contentStart = located.range.location + list.indentationLength + list.markerLength
        guard selection.location >= contentStart else { return false }

        let contentEnd = NSMaxRange(located.range)
        let indentation = located.text.substring(to: list.indentationLength)
        let changeRange: NSRange
        let replacement: String
        if list.isEmpty, selection.location == contentEnd {
            changeRange = NSRange(
                location: located.range.location + list.indentationLength,
                length: contentEnd - located.range.location - list.indentationLength
            )
            replacement = ""
        } else if let normalizedMarker = list.normalizedMarker,
                  (normalizedMarker as NSString).length != list.markerLength {
            let markerStart = located.range.location + list.indentationLength
            let contentBeforeCaret = source.substring(with: NSRange(
                location: markerStart + list.markerLength,
                length: selection.location - markerStart - list.markerLength
            ))
            changeRange = NSRange(
                location: markerStart,
                length: selection.location - markerStart
            )
            replacement = "\(normalizedMarker)\(contentBeforeCaret)\n\(indentation)" +
                list.continuationMarker
        } else {
            changeRange = selection
            replacement = "\n\(indentation)\(list.continuationMarker)"
        }

        let attributedReplacement = checkboxEditor.attributedPresentation(for: replacement)
        guard textView.shouldChangeText(
            in: changeRange,
            replacementString: attributedReplacement.string
        ) else {
            return true
        }
        textView.textStorage?.replaceCharacters(in: changeRange, with: attributedReplacement)
        textView.didChangeText()
        textView.setSelectedRange(NSRange(
            location: changeRange.location + attributedReplacement.length,
            length: 0
        ))
        return true
    }

    func textView(
        _ textView: NSTextView,
        clickedOn cell: any NSTextAttachmentCellProtocol,
        in cellFrame: NSRect,
        at charIndex: Int
    ) {
        guard cell is CheckboxAttachmentCell else { return }
        _ = toggleCheckbox(atUTF16Location: charIndex, markerHitOnly: true)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if textView.hasMarkedText() { return false }
            return handleAutomaticListReturn(in: textView)
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Mid-IME-composition, Esc belongs to the input method (plan §2.5).
            if textView.hasMarkedText() { return false }
            if !isPinned { dismiss(reason: .escape) }
            return true
        }
        return false
    }
}
