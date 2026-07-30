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
                location: (checkboxTextView.plainText as NSString).length,
                length: 0
            ))
            let undoManager = controller.undoManager(for: controller.textView)
            undoManager?.removeAllActions()

            XCTAssertTrue(panel.performKeyEquivalent(with: commandReturnEvent()))
            XCTAssertEqual(checkboxTextView.plainText, expected)

            undoManager?.undo()
            let originalState = AutomaticListLine.parse(text as NSString)?.isChecked == true
                ? "☑"
                : "☐"
            XCTAssertTrue(checkboxTextView.plainText.hasPrefix(originalState))
        }

        controller.applyToCurrentPad("☐ Caps Lock", replacing: true)
        controller.textView.setSelectedRange(NSRange(location: 11, length: 0))
        XCTAssertTrue(panel.performKeyEquivalent(with: commandReturnEvent([.command, .capsLock])))
        XCTAssertEqual(checkboxTextView.plainText, "☑ Caps Lock")
    }

    func testCommandReturnFallsThroughDuringMarkedTextAndSelection() {
        controller.applyToCurrentPad("☐ Keep editing", replacing: true)
        controller.textView.setSelectedRange(NSRange(location: 2, length: 4))

        XCTAssertFalse(panel.performKeyEquivalent(with: commandReturnEvent()))
        XCTAssertEqual(checkboxTextView.plainText, "☐ Keep editing")

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
        XCTAssertEqual(reloaded.texts[pad.id], "- [x] Saved")
        XCTAssertEqual(pad.selection, StoredSelection(utf16Location: 11, utf16Length: 0))
    }

    func testInlineCheckboxAttachmentTogglesWithoutChangingSelection() throws {
        let textView = try XCTUnwrap(controller.textView as? CheckboxTextView)
        controller.applyToCurrentPad("  ☐ Click me", replacing: true)
        let originalSelection = NSRange(location: 12, length: 0)
        textView.setSelectedRange(originalSelection)
        controller.show()
        let attachment = try XCTUnwrap(
            textView.attributedString().attribute(
                .attachment,
                at: 2,
                effectiveRange: nil
            ) as? NSTextAttachment
        )
        let cell = try XCTUnwrap(attachment.attachmentCell as? CheckboxAttachmentCell)

        controller.textView(textView, clickedOn: cell, in: .zero, at: 2)

        XCTAssertEqual(textView.plainText, "  ☑ Click me")
        XCTAssertEqual(textView.sourceText, "  - [x] Click me")
        XCTAssertEqual(textView.selectedRange(), originalSelection)
        XCTAssertGreaterThanOrEqual(cell.cellSize.width, 18)
        XCTAssertEqual(cell.cellSize.width, cell.cellSize.height)
        let updatedAttachment = try XCTUnwrap(
            textView.attributedString().attribute(
                .attachment,
                at: 2,
                effectiveRange: nil
            ) as? NSTextAttachment
        )
        let updatedCell = try XCTUnwrap(
            updatedAttachment.attachmentCell as? CheckboxAttachmentCell
        )
        XCTAssertEqual(updatedCell.cellSize, cell.cellSize)
    }

    func testDoubleClickOnAttachmentTogglesOnlyOnce() throws {
        let textView = try XCTUnwrap(controller.textView as? CheckboxTextView)
        controller.applyToCurrentPad("- [ ] Double click", replacing: true)
        controller.show()
        let checkboxPoint = try point(forCharacterAt: 0, in: textView)

        textView.mouseDown(with: try mouseEvent(
            .leftMouseDown,
            at: checkboxPoint,
            in: textView,
            clickCount: 1
        ))
        textView.mouseUp(with: try mouseEvent(
            .leftMouseUp,
            at: checkboxPoint,
            in: textView,
            clickCount: 1
        ))
        XCTAssertEqual(textView.plainText, "☑ Double click")

        textView.mouseDown(with: try mouseEvent(
            .leftMouseDown,
            at: checkboxPoint,
            in: textView,
            clickCount: 2
        ))
        textView.mouseUp(with: try mouseEvent(
            .leftMouseUp,
            at: checkboxPoint,
            in: textView,
            clickCount: 2
        ))
        XCTAssertEqual(textView.plainText, "☑ Double click")
    }

    func testMarkdownProjectionMapsSelectionAndSerializesWithoutReplacementCharacters() throws {
        let textView = try XCTUnwrap(controller.textView as? CheckboxTextView)
        controller.applyToCurrentPad("Before\n- [ ] task\nAfter", replacing: true)

        XCTAssertEqual(textView.plainText, "Before\n☐ task\nAfter")
        XCTAssertEqual(textView.sourceText, "Before\n- [ ] task\nAfter")
        XCTAssertFalse(textView.sourceText.contains("\u{FFFC}"))
        XCTAssertEqual(
            textView.displayRange(forSourceRange: NSRange(location: 13, length: 4)),
            NSRange(location: 9, length: 4)
        )
        XCTAssertEqual(
            textView.sourceRange(forDisplayRange: NSRange(location: 9, length: 4)),
            NSRange(location: 13, length: 4)
        )
    }

    func testTypingMarkerTerminatingSpaceCreatesAttachmentBeforePersistence() throws {
        let textView = try XCTUnwrap(controller.textView as? CheckboxTextView)
        textView.string = "- [ ]"
        textView.setSelectedRange(NSRange(location: 5, length: 0))

        textView.insertText(" ", replacementRange: textView.selectedRange())

        XCTAssertEqual(textView.plainText, "☐ ")
        XCTAssertEqual(textView.sourceText, "- [ ] ")
        XCTAssertNotNil(textView.attributedString().attribute(
            .attachment,
            at: 0,
            effectiveRange: nil
        ))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testTypingDashStaysPlainAndAsteriskCreatesDisplayedBullet() throws {
        let textView = try XCTUnwrap(controller.textView as? CheckboxTextView)

        textView.string = "-"
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.insertText(" ", replacementRange: textView.selectedRange())

        XCTAssertEqual(textView.plainText, "- ")
        XCTAssertEqual(textView.sourceText, "- ")

        textView.string = "*"
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.insertText(" ", replacementRange: textView.selectedRange())

        XCTAssertEqual(textView.plainText, "• ")
        XCTAssertEqual(textView.sourceText, "* ")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
    }

    func testReturnContinuesAndExitsNumberedLists() {
        controller.applyToCurrentPad("8. eighth", replacing: true)
        controller.textView.setSelectedRange(NSRange(location: 9, length: 0))

        XCTAssertTrue(controller.textView(
            controller.textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        XCTAssertEqual(controller.textView.string, "8. eighth\n9. ")

        XCTAssertTrue(controller.textView(
            controller.textView,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        XCTAssertEqual(controller.textView.string, "8. eighth\n")
    }

    private var checkboxTextView: CheckboxTextView {
        controller.textView as! CheckboxTextView
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
        let localPoint = NSPoint(
            x: bounds.midX + textView.textContainerOrigin.x,
            y: bounds.midY + textView.textContainerOrigin.y
        )
        return textView.convert(localPoint, to: nil)
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        at windowPoint: NSPoint,
        in textView: NSTextView,
        clickCount: Int
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: windowPoint,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: type == .leftMouseDown ? 1 : 0
        ))
    }

}
