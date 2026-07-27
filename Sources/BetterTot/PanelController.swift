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

final class ScratchpadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var onTogglePin: (() -> Void)?
    var onPadCommand: ((PadCommand) -> Void)?
    var onOpenSettings: (() -> Void)?

    // ponytail: accessory app has no menu bar, so standard edit key equivalents
    // are routed by hand here; replace with a real main menu when settings land.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard event.modifierFlags.contains(.command) else { return false }
        let shift = event.modifierFlags.contains(.shift)
        let option = event.modifierFlags.contains(.option)
        let control = event.modifierFlags.contains(.control)

        switch event.keyCode {
        // Bare ⌘ only (plan §4.3) — ⇧⌘←/⌥⌘← etc. stay text-selection commands.
        case 123 where !shift && !option && !control: onPadCommand?(.previous); return true
        case 124 where !shift && !option && !control: onPadCommand?(.next); return true
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
        case "q": NSApp.terminate(nil); return true
        default: return false
        }
    }
}

@MainActor
final class PanelController: NSObject, NSTextViewDelegate {
    private let statusItem: NSStatusItem
    let store: WorkspaceStore
    private let defaults: UserDefaults
    private let panel: ScratchpadPanel
    let textView: NSTextView
    private let scrollView: NSScrollView
    private let segmented: NSSegmentedControl

    private var pads: [PadMetadata]
    private var selectedIndex: Int
    private var texts: [PadID: String]
    private var revisions: [PadID: UInt64] = [:]
    private var undoManagers: [PadID: UndoManager] = [:]

    private var isPinned = false
    private var pendingSave: DispatchWorkItem?
    private var mouseMonitors: [Any] = []
    private var editingSuspensionCount = 0
    private var editableBeforeSuspension = true
    var onOpenSettings: (() -> Void)?

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

        scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as! NSTextView
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.drawsBackground = false
        scrollView.drawsBackground = false

        segmented = NSSegmentedControl(
            labels: (1...WorkspaceMetadata.padCount).map(String.init),
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        segmented.selectedSegment = selectedIndex
        segmented.refusesFirstResponder = true // keyboard path is ⌘1–7
        segmented.setAccessibilityLabel("Scratchpads")
        for index in 0..<WorkspaceMetadata.padCount {
            segmented.setToolTip("Scratchpad \(index + 1)", forSegment: index)
        }

        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true

        let stack = NSStackView(views: [segmented, scrollView])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -8),
        ])

        panel = ScratchpadPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 340),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = background

        super.init()

        segmented.target = self
        segmented.action = #selector(segmentChanged)
        textView.delegate = self
        panel.onTogglePin = { [weak self] in self?.togglePin() }
        panel.onPadCommand = { [weak self] command in self?.handle(command) }
        panel.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        applySettings()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(defaultsChanged),
            name: UserDefaults.didChangeNotification,
            object: defaults
        )
        loadSelectedPadIntoEditor()
    }

    // MARK: - Settings

    @objc private func defaultsChanged() {
        applySettings()
    }

    func applySettings() {
        textView.font = SettingsKeys.editorFont(in: defaults)
        textView.isContinuousSpellCheckingEnabled = defaults.bool(forKey: SettingsKeys.spellChecking)
        textView.isAutomaticQuoteSubstitutionEnabled = defaults.bool(forKey: SettingsKeys.smartQuotes)
        textView.isAutomaticDashSubstitutionEnabled = defaults.bool(forKey: SettingsKeys.smartDashes)
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
            pasteboard.setString(textView.string, forType: .string)
        case .clear:
            clearCurrentPad()
        }
    }

    @objc private func segmentChanged() {
        switchToPad(at: segmented.selectedSegment)
        panel.makeFirstResponder(textView)
    }

    private func switchToPad(at index: Int) {
        guard pads.indices.contains(index), index != selectedIndex else {
            segmented.selectedSegment = selectedIndex
            return
        }
        persistCurrentPadUIState()
        commitCurrentPadNow()
        selectedIndex = index
        segmented.selectedSegment = index
        loadSelectedPadIntoEditor()
        announceSelectedPad()
        let id = pads[index].id
        Task { await store.select(id) }
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
                .announcement: "Scratchpad \(pad.position + 1)\(suffix)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    private func loadSelectedPadIntoEditor() {
        let pad = pads[selectedIndex]
        textView.setAccessibilityLabel("Scratchpad \(pad.position + 1)")
        textView.string = texts[pad.id] ?? ""
        let length = (textView.string as NSString).length
        textView.setSelectedRange(pad.selection.clamped(toTextLength: length))
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let maxOffset = max(0, textView.frame.height - scrollView.contentView.bounds.height)
        let offset = min(max(0, pad.scrollOffset), maxOffset)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: offset))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func persistCurrentPadUIState() {
        let range = textView.selectedRange()
        let selection = StoredSelection(utf16Location: range.location, utf16Length: range.length)
        let offset = Double(scrollView.contentView.bounds.origin.y)
        pads[selectedIndex].selection = selection
        pads[selectedIndex].scrollOffset = offset
        let id = pads[selectedIndex].id
        Task { await store.updatePadState(id, selection: selection, scrollOffset: offset) }
    }

    // Undoable clear (plan §4.3: clearing needs confirmation or immediate undo).
    private func clearCurrentPad() {
        let full = NSRange(location: 0, length: (textView.string as NSString).length)
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
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(textView)
        if !isPinned { installMouseMonitors() }
    }

    func dismiss(reason: PanelDismissalReason) {
        if isPinned {
            switch reason {
            case .explicitClose, .termination:
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
        isPinned.toggle()
        panel.isMovableByWindowBackground = isPinned
        if isPinned {
            removeMouseMonitors()
        } else if panel.isVisible {
            installMouseMonitors()
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
        panel.setFrameOrigin(origin)
    }

    // MARK: - Outside-click monitors (installed only while an unpinned panel is visible)

    private func installMouseMonitors() {
        guard mouseMonitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.dismiss(reason: .outsideClick)
        }) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            guard let self else { return event }
            // ignore clicks inside the panel and on the status item (its action handles the toggle)
            if event.window !== self.panel, event.window !== self.statusItem.button?.window {
                self.dismiss(reason: .outsideClick)
            }
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func removeMouseMonitors() {
        mouseMonitors.forEach(NSEvent.removeMonitor)
        mouseMonitors = []
    }

    // MARK: - Persistence (journal per change, 200 ms debounced commit)

    func textDidChange(_ notification: Notification) {
        let id = pads[selectedIndex].id
        let text = textView.string
        texts[id] = text
        let revision = (revisions[id] ?? 0) + 1
        revisions[id] = revision
        Task { _ = await store.journal(id, text: text, revision: revision) }

        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.commit(id) }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func commit(_ id: PadID) {
        guard let text = texts[id], let revision = revisions[id] else { return }
        Task { await store.commit(id, text: text, revision: revision) }
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
        let length = (textView.string as NSString).length
        let range: NSRange
        var insert = text
        if replacing {
            range = NSRange(location: 0, length: length)
        } else {
            range = NSRange(location: length, length: 0)
            if length > 0, !textView.string.hasSuffix("\n") {
                insert = "\n" + insert
            }
        }
        guard textView.shouldChangeText(in: range, replacementString: insert) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: insert)
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

    // MARK: - Escape dismisses; Return is deliberately untouched (plan §4.4)

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            // Mid-IME-composition, Esc belongs to the input method (plan §2.5).
            if textView.hasMarkedText() { return false }
            if !isPinned { dismiss(reason: .escape) }
            return true
        }
        return false
    }
}
