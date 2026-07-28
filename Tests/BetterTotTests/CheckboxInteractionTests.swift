import AppKit
import XCTest
@testable import BetterTot

@MainActor
final class CheckboxInteractionTests: XCTestCase {
    private var root: URL!
    private var statusItem: NSStatusItem!
    private var store: WorkspaceStore!
    private var controller: PanelController!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettertot-checkbox-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        store = WorkspaceStore(root: root)
        let snapshot = try await store.load()
        controller = PanelController(statusItem: statusItem, store: store, snapshot: snapshot)
    }

    override func tearDown() async throws {
        controller?.dismiss(reason: .explicitClose)
        _ = await controller?.flushAll()
        controller = nil
        store = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        try? FileManager.default.removeItem(at: root)
    }

    func testCommandReturnTogglesUnicodeAndLegacyCheckboxesWithUndo() {
        let cases = [
            ("☐ Ship release", "☑ Ship release"),
            ("☑ Ship release", "☐ Ship release"),
            ("- [ ] Legacy task", "☑ Legacy task"),
            ("- [x] Legacy task", "☐ Legacy task"),
            ("- [ ] café 👩🏽‍💻", "☑ café 👩🏽‍💻"),
        ]

        for (text, expected) in cases {
            controller.applyToCurrentPad(text, replacing: true)
            controller.textView.setSelectedRange(NSRange(
                location: (text as NSString).length,
                length: 0
            ))
            let undoManager = controller.undoManager(for: controller.textView)
            undoManager?.removeAllActions()

            XCTAssertTrue(panel.performKeyEquivalent(with: commandReturnEvent()))
            XCTAssertEqual(controller.textView.string, expected)

            undoManager?.undo()
            XCTAssertEqual(controller.textView.string, text)
        }

        controller.applyToCurrentPad("☐ Caps Lock", replacing: true)
        controller.textView.setSelectedRange(NSRange(location: 11, length: 0))
        XCTAssertTrue(panel.performKeyEquivalent(with: commandReturnEvent([.command, .capsLock])))
        XCTAssertEqual(controller.textView.string, "☑ Caps Lock")
    }

    func testCommandReturnFallsThroughDuringMarkedTextAndSelection() {
        controller.applyToCurrentPad("☐ Keep editing", replacing: true)
        controller.textView.setSelectedRange(NSRange(location: 2, length: 4))

        XCTAssertFalse(panel.performKeyEquivalent(with: commandReturnEvent()))
        XCTAssertEqual(controller.textView.string, "☐ Keep editing")

        controller.textView.setMarkedText(
            "composing",
            selectedRange: NSRange(location: 9, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertFalse(panel.performKeyEquivalent(with: commandReturnEvent()))
        XCTAssertTrue(controller.textView.hasMarkedText())
        controller.textView.unmarkText()
    }

    func testCheckboxTogglePersistsConvertedTextAndCaret() async throws {
        controller.applyToCurrentPad("- [ ] Saved", replacing: true)
        controller.textView.setSelectedRange(NSRange(location: 11, length: 0))

        XCTAssertTrue(panel.performKeyEquivalent(with: commandReturnEvent()))
        await controller.flushAll()

        let reloaded = try await WorkspaceStore(root: root).load()
        let pad = reloaded.metadata.pads.sorted { $0.position < $1.position }[0]
        XCTAssertEqual(reloaded.texts[pad.id], "☑ Saved")
        XCTAssertEqual(pad.selection, StoredSelection(utf16Location: 7, utf16Length: 0))
    }

    func testCheckboxClickAllowsJitterAndRejectsModifiersAndDrags() throws {
        let textView = try XCTUnwrap(controller.textView as? CheckboxTextView)
        controller.applyToCurrentPad("  ☐ Click me", replacing: true)
        controller.show()
        let checkboxPoint = try point(forCharacterAt: 2, in: textView)

        textView.mouseDown(with: try mouseEvent(.leftMouseDown, at: checkboxPoint, in: textView))
        textView.mouseUp(with: try mouseEvent(.leftMouseUp, at: checkboxPoint, in: textView))
        XCTAssertEqual(textView.string, "  ☑ Click me")

        let jitterPoint = NSPoint(x: checkboxPoint.x + 2, y: checkboxPoint.y + 1)
        textView.mouseDown(with: try mouseEvent(.leftMouseDown, at: checkboxPoint, in: textView))
        textView.mouseDragged(with: try mouseEvent(.leftMouseDragged, at: jitterPoint, in: textView))
        textView.mouseUp(with: try mouseEvent(.leftMouseUp, at: jitterPoint, in: textView))
        XCTAssertEqual(textView.string, "  ☐ Click me")

        textView.mouseDown(with: try mouseEvent(
            .leftMouseDown, at: checkboxPoint, in: textView, modifiers: .shift
        ))
        textView.mouseUp(with: try mouseEvent(
            .leftMouseUp, at: checkboxPoint, in: textView, modifiers: .shift
        ))
        XCTAssertEqual(textView.string, "  ☐ Click me")

        let dragPoint = NSPoint(x: checkboxPoint.x + 20, y: checkboxPoint.y)
        textView.mouseDown(with: try mouseEvent(.leftMouseDown, at: checkboxPoint, in: textView))
        textView.mouseDragged(with: try mouseEvent(.leftMouseDragged, at: dragPoint, in: textView))
        textView.mouseUp(with: try mouseEvent(.leftMouseUp, at: dragPoint, in: textView))
        XCTAssertEqual(textView.string, "  ☐ Click me")
    }

    private var panel: ScratchpadPanel {
        controller.textView.window as! ScratchpadPanel
    }

    private func commandReturnEvent(
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )!
    }

    private func point(forCharacterAt index: Int, in textView: NSTextView) throws -> NSPoint {
        let layoutManager = try XCTUnwrap(textView.layoutManager)
        let textContainer = try XCTUnwrap(textView.textContainer)
        layoutManager.ensureLayout(for: textContainer)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: index)
        let bounds = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        )
        return NSPoint(
            x: bounds.midX + textView.textContainerOrigin.x,
            y: bounds.midY + textView.textContainerOrigin.y
        )
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        at localPoint: NSPoint,
        in textView: NSTextView,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: textView.convert(localPoint, to: nil),
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0
        ))
    }
}
