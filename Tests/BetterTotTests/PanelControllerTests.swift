import AppKit
import XCTest
@testable import BetterTot

@MainActor
final class PanelControllerTests: XCTestCase {
    private var root: URL!
    private var statusItem: NSStatusItem!
    private var store: WorkspaceStore!
    private var snapshot: WorkspaceSnapshot!
    private var controller: PanelController!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettertot-panel-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        store = WorkspaceStore(root: root)
        snapshot = try await store.load()
        controller = PanelController(statusItem: statusItem, store: store, snapshot: snapshot)
    }

    override func tearDown() async throws {
        controller?.dismiss(reason: .explicitClose)
        await Task.yield()
        if let store {
            _ = await store.currentMetadata()
        }
        controller = nil
        store = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        try? FileManager.default.removeItem(at: root)
    }

    func testPressingReturnDoesNotDismissPanel() {
        controller.show()
        controller.applyToCurrentPad("before", replacing: true)
        controller.textView.setSelectedRange(NSRange(location: 6, length: 0))

        let handled = controller.textView(
            controller.textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:)))
        controller.textView.insertNewline(nil)
        controller.applyToCurrentPad("after", replacing: false)

        XCTAssertFalse(handled, "Return must remain an editor command")
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(controller.textView.string, "before\nafter")

        controller.dismiss(reason: .statusItemToggle)
        controller.show()
        XCTAssertEqual(controller.textView.string, "before\nafter")
    }

    func testEscapeDismissesUnpinnedPanelWithoutDestroyingText() async throws {
        controller.show()
        controller.applyToCurrentPad("survives escape", replacing: true)

        let handled = controller.textView(
            controller.textView,
            doCommandBy: #selector(NSResponder.cancelOperation(_:)))

        XCTAssertTrue(handled)
        XCTAssertFalse(panel.isVisible)
        controller.show()
        XCTAssertEqual(controller.textView.string, "survives escape")

        await controller.flushAll()
        let reloaded = try await WorkspaceStore(root: root).load()
        XCTAssertEqual(reloaded.texts[orderedPads[0].id], "survives escape")
    }

    func testEscapeDoesNotDismissPinnedPanel() {
        controller.show()
        panel.onTogglePin?()

        let handled = controller.textView(
            controller.textView,
            doCommandBy: #selector(NSResponder.cancelOperation(_:)))

        XCTAssertTrue(handled)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.isMovableByWindowBackground)
    }

    func testOutsideClickDoesNotDismissPinnedPanel() {
        controller.show()
        panel.onTogglePin?()

        controller.dismiss(reason: .outsideClick)

        XCTAssertTrue(panel.isVisible)
    }

    func testPinningDoesNotRecreateEditorOrUndoHistory() {
        controller.applyToCurrentPad("draft", replacing: true)
        let editor = controller.textView
        let undoManager = controller.undoManager(for: editor)

        panel.onTogglePin?()
        panel.onTogglePin?()

        XCTAssertTrue(editor === controller.textView)
        XCTAssertTrue(undoManager === controller.undoManager(for: controller.textView))
        undoManager?.undo()
        XCTAssertEqual(controller.textView.string, "")
    }

    func testDraggingAttachedPanelPinsWithoutLosingEditorState() {
        controller.show()
        controller.applyToCurrentPad("dragged draft", replacing: true)
        controller.textView.setSelectedRange(NSRange(location: 3, length: 4))
        let editor = controller.textView
        let undoManager = controller.undoManager(for: editor)
        let attachedOrigin = panel.frame.origin

        panel.setFrameOrigin(NSPoint(x: attachedOrigin.x + 24, y: attachedOrigin.y - 18))
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: panel))
        controller.dismiss(reason: .outsideClick)

        XCTAssertTrue(panel.isVisible, "a user-moved panel must become pinned")
        XCTAssertTrue(editor === controller.textView)
        XCTAssertTrue(undoManager === controller.undoManager(for: controller.textView))
        XCTAssertEqual(controller.textView.string, "dragged draft")
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 3, length: 4))
    }

    func testProgrammaticAttachmentDoesNotPinPanel() {
        controller.show()

        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: panel))
        controller.dismiss(reason: .outsideClick)

        XCTAssertFalse(panel.isVisible)
    }

    func testToggleDismissesUnpinnedPanelButKeepsPinnedPanelVisible() {
        controller.toggle(reason: .statusItemToggle)
        XCTAssertTrue(panel.isVisible)

        controller.toggle(reason: .statusItemToggle)
        XCTAssertFalse(panel.isVisible)

        controller.show()
        panel.onTogglePin?()
        controller.toggle(reason: .globalShortcutToggle)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.firstResponder === controller.textView)
    }

    func testPanelCommandsNavigateCopyAndClearWithUndo() {
        controller.applyToCurrentPad("copy me", replacing: true)
        controller.undoManager(for: controller.textView)?.removeAllActions()

        panel.onPadCommand?(.next)
        XCTAssertEqual(controller.currentPadPosition, 1)
        panel.onPadCommand?(.previous)
        XCTAssertEqual(controller.currentPadPosition, 0)

        panel.onPadCommand?(.copyAll)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "copy me")

        panel.onPadCommand?(.clear)
        XCTAssertEqual(controller.textView.string, "")
        controller.undoManager(for: controller.textView)?.undo()
        XCTAssertEqual(controller.textView.string, "copy me")

        panel.onPadCommand?(.select(2))
        XCTAssertEqual(controller.currentPadPosition, 2)
    }

    func testModifiedClearShortcutRemainsAnEditorCommand() {
        controller.applyToCurrentPad("keep me", replacing: true)
        let event = keyEvent(keyCode: 51, modifiers: [.command, .shift, .option])

        XCTAssertFalse(panel.performKeyEquivalent(with: event))
        XCTAssertEqual(controller.textView.string, "keep me")
    }

    func testScratchpadPanelRoutesDocumentedKeyCommands() {
        controller.applyToCurrentPad("copy then clear", replacing: true)

        XCTAssertFalse(panel.performKeyEquivalent(with: keyEvent(
            keyCode: 11, characters: "b", modifiers: [])))
        XCTAssertTrue(panel.performKeyEquivalent(with: keyEvent(
            keyCode: 124, modifiers: [.command])))
        XCTAssertEqual(controller.currentPadPosition, 1)
        XCTAssertTrue(panel.performKeyEquivalent(with: keyEvent(
            keyCode: 123, modifiers: [.command])))
        XCTAssertEqual(controller.currentPadPosition, 0)

        XCTAssertTrue(panel.performKeyEquivalent(with: keyEvent(
            keyCode: 20, characters: "3", modifiers: [.command])))
        XCTAssertEqual(controller.currentPadPosition, 2)
        XCTAssertTrue(panel.performKeyEquivalent(with: keyEvent(
            keyCode: 18, characters: "1", modifiers: [.command])))
        XCTAssertEqual(controller.currentPadPosition, 0)

        XCTAssertTrue(panel.performKeyEquivalent(with: keyEvent(
            keyCode: 8, characters: "c", modifiers: [.command, .shift])))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "copy then clear")
        XCTAssertTrue(panel.performKeyEquivalent(with: keyEvent(
            keyCode: 51, modifiers: [.command, .shift])))
        XCTAssertEqual(controller.textView.string, "")

        controller.show()
        XCTAssertTrue(panel.performKeyEquivalent(with: keyEvent(
            keyCode: 35, characters: "p", modifiers: [.command])))
        controller.dismiss(reason: .outsideClick)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.performKeyEquivalent(with: keyEvent(
            keyCode: 35, characters: "p", modifiers: [.command])))
        controller.dismiss(reason: .outsideClick)
        XCTAssertFalse(panel.isVisible)

        var didOpenSettings = false
        controller.onOpenSettings = { didOpenSettings = true }
        XCTAssertTrue(panel.performKeyEquivalent(with: keyEvent(
            keyCode: 43, characters: ",", modifiers: [.command])))
        XCTAssertTrue(didOpenSettings)

        XCTAssertFalse(panel.performKeyEquivalent(with: keyEvent(
            keyCode: 124, modifiers: [.command, .shift])))
        XCTAssertFalse(panel.performKeyEquivalent(with: keyEvent(
            keyCode: 11, characters: "b", modifiers: [.command])))
    }

    func testPadDotsUseColorsAndAccessibleNumericIdentities() throws {
        let segmented = try XCTUnwrap(descendant(of: panel.contentView, as: NSSegmentedControl.self))

        XCTAssertEqual(segmented.segmentCount, WorkspaceMetadata.padCount)
        XCTAssertEqual(segmented.selectedSegment, 0)
        let images = try (0..<WorkspaceMetadata.padCount).map { index in
            XCTAssertEqual(segmented.label(forSegment: index), "")
            XCTAssertEqual(segmented.toolTip(forSegment: index), "Scratchpad \(index + 1)")
            let image = try XCTUnwrap(segmented.image(forSegment: index))
            XCTAssertEqual(image.accessibilityDescription, "Scratchpad \(index + 1)")
            return image
        }
        let renderedDots = Set(images.compactMap(\.tiffRepresentation))
        XCTAssertEqual(renderedDots.count, WorkspaceMetadata.padCount)
    }

    func testPadDotSelectionRestoresEditorFocusAndRejectsInvalidPads() {
        controller.show()
        let segmented = descendant(of: panel.contentView, as: NSSegmentedControl.self)!
        segmented.selectedSegment = 1

        XCTAssertTrue(segmented.sendAction(segmented.action, to: segmented.target))
        XCTAssertEqual(controller.currentPadPosition, 1)
        XCTAssertTrue(panel.firstResponder === controller.textView)

        controller.selectPad(at: 1)
        controller.selectPad(at: -1)
        controller.selectPad(at: WorkspaceMetadata.padCount)
        XCTAssertEqual(controller.currentPadPosition, 1)
        XCTAssertEqual(segmented.selectedSegment, 1)
    }

    func testSettingsButtonInsidePanelInvokesCallback() throws {
        var openCount = 0
        controller.onOpenSettings = { openCount += 1 }
        let button = try XCTUnwrap(
            descendants(of: panel.contentView, as: NSButton.self).first {
                $0.identifier?.rawValue == "panel-settings"
            })

        XCTAssertNotNil(button.image)
        XCTAssertEqual(button.toolTip, "Settings")
        XCTAssertEqual(button.accessibilityLabel(), "Settings")
        XCTAssertTrue(button.sendAction(button.action, to: button.target))
        XCTAssertEqual(openCount, 1)
    }

    func testStatusItemClickIsNotHandledAsOutsideClickBeforeToggle() throws {
        controller.show()
        let button = try XCTUnwrap(statusItem.button)
        let buttonWindow = try XCTUnwrap(button.window)
        let frame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))

        controller.handleOutsideClick(
            window: nil,
            screenLocation: NSPoint(x: frame.midX, y: frame.midY))
        XCTAssertTrue(panel.isVisible)

        controller.toggle(reason: .statusItemToggle)
        XCTAssertFalse(panel.isVisible, "the status-item action must close without reopening")

        controller.show()
        controller.handleOutsideClick(
            window: nil,
            screenLocation: NSPoint(x: frame.maxX + 100, y: frame.minY - 100))
        XCTAssertFalse(panel.isVisible)
    }

    func testEscapeDuringMarkedTextRemainsAnInputMethodCommand() {
        controller.show()
        controller.textView.setMarkedText(
            "composing",
            selectedRange: NSRange(location: 9, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(controller.textView.hasMarkedText())

        let handled = controller.textView(
            controller.textView,
            doCommandBy: #selector(NSResponder.cancelOperation(_:)))

        XCTAssertFalse(handled)
        XCTAssertTrue(panel.isVisible)
        controller.textView.unmarkText()
    }

    func testRepeatedShowKeepsEditorFocused() {
        controller.show()
        controller.show()

        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(panel.firstResponder === controller.textView)
    }

    func testPadSwitchPreservesContentSelectionAndIsolatesUndo() {
        controller.applyToCurrentPad("pad one", replacing: true)
        controller.textView.setSelectedRange(NSRange(location: 4, length: 3))
        let firstUndoManager = controller.undoManager(for: controller.textView)

        controller.selectPad(at: 1)
        controller.applyToCurrentPad("pad two", replacing: true)
        let secondUndoManager = controller.undoManager(for: controller.textView)

        XCTAssertFalse(firstUndoManager === secondUndoManager)
        secondUndoManager?.undo()
        XCTAssertEqual(controller.textView.string, "")

        controller.selectPad(at: 0)
        XCTAssertEqual(controller.textView.string, "pad one")
        XCTAssertEqual(controller.textView.selectedRange(), NSRange(location: 4, length: 3))
    }

    func testReplaceAndAppendUseEditorChangePipeline() {
        controller.applyToCurrentPad("original", replacing: true)
        let undoManager = controller.undoManager(for: controller.textView)
        undoManager?.removeAllActions()

        controller.applyToCurrentPad("replacement", replacing: true)
        XCTAssertEqual(controller.textView.string, "replacement")
        undoManager?.undo()
        XCTAssertEqual(controller.textView.string, "original")

        controller.applyToCurrentPad("appended", replacing: false)
        XCTAssertEqual(controller.textView.string, "original\nappended")
        undoManager?.undo()
        XCTAssertEqual(controller.textView.string, "original")

        controller.applyToCurrentPad("tail\n", replacing: true)
        controller.applyToCurrentPad("next", replacing: false)
        XCTAssertEqual(controller.textView.string, "tail\nnext")
    }

    func testFlushPersistsEveryEditedPadAndSelectedPadState() async throws {
        controller.applyToCurrentPad("first", replacing: true)
        controller.textView.setSelectedRange(NSRange(location: 2, length: 2))
        controller.selectPad(at: 1)
        controller.applyToCurrentPad("second", replacing: true)
        controller.textView.setSelectedRange(NSRange(location: 3, length: 0))

        await controller.flushAll()

        let reloaded = try await WorkspaceStore(root: root).load()
        let pads = reloaded.metadata.pads.sorted { $0.position < $1.position }
        XCTAssertEqual(reloaded.texts[pads[0].id], "first")
        XCTAssertEqual(reloaded.texts[pads[1].id], "second")
        XCTAssertEqual(reloaded.metadata.selectedPadID, pads[1].id)
        XCTAssertEqual(pads[0].selection, StoredSelection(utf16Location: 2, utf16Length: 2))
        XCTAssertEqual(pads[1].selection, StoredSelection(utf16Location: 3, utf16Length: 0))

        let restoredController = PanelController(
            statusItem: statusItem,
            store: WorkspaceStore(root: root),
            snapshot: reloaded)
        XCTAssertEqual(restoredController.currentPadPosition, 1)
        XCTAssertEqual(restoredController.textView.string, "second")
        XCTAssertEqual(restoredController.textView.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testPanelUsesInjectedEditorDefaults() async throws {
        let suiteName = "bettertot-panel-defaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.register(defaults: SettingsKeys.defaults)
        defaults.set(false, forKey: SettingsKeys.spellChecking)
        defaults.set(true, forKey: SettingsKeys.smartQuotes)
        defaults.set(true, forKey: SettingsKeys.smartDashes)
        defaults.set(19.0, forKey: SettingsKeys.fontSize)

        let injected = PanelController(
            statusItem: statusItem,
            store: store,
            snapshot: snapshot,
            defaults: defaults
        )

        XCTAssertFalse(injected.textView.isContinuousSpellCheckingEnabled)
        XCTAssertTrue(injected.textView.isAutomaticQuoteSubstitutionEnabled)
        XCTAssertTrue(injected.textView.isAutomaticDashSubstitutionEnabled)
        XCTAssertEqual(injected.textView.font?.pointSize, 19)
        injected.dismiss(reason: .explicitClose)
    }

    func testEditingIsSuspendedOnlyForSnapshotOperation() async throws {
        XCTAssertTrue(controller.textView.isEditable)

        let wasSuspended = await controller.withEditingSuspended {
            XCTAssertFalse(controller.textView.isEditable)
            let nestedWasSuspended = await controller.withEditingSuspended {
                !controller.textView.isEditable
            }
            XCTAssertFalse(controller.textView.isEditable)
            return nestedWasSuspended
        }

        XCTAssertTrue(wasSuspended)
        XCTAssertTrue(controller.textView.isEditable)
    }

    func testRestoreUpdatesEachPadAndDropsForeignUndoHistory() async throws {
        controller.applyToCurrentPad("local edit", replacing: true)
        XCTAssertTrue(controller.undoManager(for: controller.textView)?.canUndo == true)

        let backup = root.appendingPathComponent("restore", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try "restored first".write(
            to: backup.appendingPathComponent("Pad 1.txt"), atomically: true, encoding: .utf8)
        try "restored second".write(
            to: backup.appendingPathComponent("Pad 2.txt"), atomically: true, encoding: .utf8)
        let files = (1...WorkspaceMetadata.padCount).map {
            backup.appendingPathComponent("Pad \($0).txt")
        }

        let skipped = await controller.restore(from: files)
        XCTAssertEqual(skipped, [])
        XCTAssertEqual(controller.textView.string, "restored first")
        XCTAssertFalse(controller.undoManager(for: controller.textView)?.canUndo == true)
        controller.selectPad(at: 1)
        XCTAssertEqual(controller.textView.string, "restored second")
    }

    private var panel: ScratchpadPanel {
        controller.textView.window as! ScratchpadPanel
    }

    private var orderedPads: [PadMetadata] {
        snapshot.metadata.pads.sorted { $0.position < $1.position }
    }

    private func keyEvent(
        keyCode: UInt16,
        characters: String = "",
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode)!
    }

    private func descendant<T: NSView>(of view: NSView?, as type: T.Type) -> T? {
        guard let view else { return nil }
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { self.descendant(of: $0, as: type) }.first
    }

    private func descendants<T: NSView>(of view: NSView?, as type: T.Type) -> [T] {
        guard let view else { return [] }
        let current = (view as? T).map { [$0] } ?? []
        return current + view.subviews.flatMap { descendants(of: $0, as: type) }
    }
}
