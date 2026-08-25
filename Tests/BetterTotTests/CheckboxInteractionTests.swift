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

    func testMarkdownRendersWithoutChangingStoredSource() throws {
        let textView = try XCTUnwrap(controller.textView as? CheckboxTextView)
        let source = "# Heading\n**bold** *italic* `code` [link](https://example.com)\n- [ ] **task**"

        controller.applyToCurrentPad(source, replacing: true)

        XCTAssertEqual(textView.sourceText, source)
        let rendered = textView.attributedString()
        let display = rendered.string as NSString
        let headingFont = try XCTUnwrap(rendered.attribute(
            .font,
            at: display.range(of: "Heading").location,
            effectiveRange: nil
        ) as? NSFont)
        let boldFont = try XCTUnwrap(rendered.attribute(
            .font,
            at: display.range(of: "bold").location,
            effectiveRange: nil
        ) as? NSFont)
        let italicFont = try XCTUnwrap(rendered.attribute(
            .font,
            at: display.range(of: "italic").location,
            effectiveRange: nil
        ) as? NSFont)
        let codeFont = try XCTUnwrap(rendered.attribute(
            .font,
            at: display.range(of: "code").location,
            effectiveRange: nil
        ) as? NSFont)
        let boldColor = try XCTUnwrap(rendered.attribute(
            .foregroundColor,
            at: display.range(of: "bold").location,
            effectiveRange: nil
        ) as? NSColor)
        let linkRange = display.range(of: "link")
        let hiddenMarkerFont = try XCTUnwrap(rendered.attribute(
            .font,
            at: 0,
            effectiveRange: nil
        ) as? NSFont)
        let hiddenMarkerColor = try XCTUnwrap(rendered.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor)

        XCTAssertGreaterThan(headingFont.pointSize, boldFont.pointSize)
        XCTAssertTrue(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(italicFont.fontDescriptor.symbolicTraits.contains(.italic))
        XCTAssertTrue(codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertEqual(
            boldColor,
            PanelContentView.padColor(for: controller.padMetadata[0])
        )
        XCTAssertLessThan(hiddenMarkerFont.pointSize, 1)
        XCTAssertEqual(hiddenMarkerColor.alphaComponent, 0)
        XCTAssertEqual(
            rendered.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL,
            URL(string: "https://example.com")
        )
        XCTAssertNotNil(rendered.attribute(
            .attachment,
            at: display.range(of: "\u{FFFC}").location,
            effectiveRange: nil
        ))
        XCTAssertEqual(textView.visibleText, "Heading\nbold italic code link\n☐ task")
        XCTAssertEqual(
            textView.sourceSafeRange(forVisibleSelection: display.range(of: "bold")),
            display.range(of: "**bold**")
        )
        textView.setSelectedRange(display.range(of: "bold"))
        textView.copy(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "**bold**")
    }

    func testCommandFormattingShortcutsToggleMarkdownBackedStyles() throws {
        let cases: [(keyCode: UInt16, key: String, source: String)] = [
            (11, "b", "**Format me**"),
            (34, "i", "*Format me*"),
            (32, "u", "<u>Format me</u>"),
        ]

        for item in cases {
            controller.applyToCurrentPad("Format me", replacing: true)
            checkboxTextView.setSelectedRange(NSRange(location: 0, length: 9))

            XCTAssertTrue(panel.performKeyEquivalent(with: commandKeyEvent(
                keyCode: item.keyCode,
                characters: item.key
            )))
            XCTAssertEqual(checkboxTextView.sourceText, item.source)

            let rendered = checkboxTextView.attributedString()
            let contentRange = (rendered.string as NSString).range(of: "Format me")
            switch item.key {
            case "b":
                let font = try XCTUnwrap(rendered.attribute(
                    .font,
                    at: contentRange.location,
                    effectiveRange: nil
                ) as? NSFont)
                XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
            case "i":
                let font = try XCTUnwrap(rendered.attribute(
                    .font,
                    at: contentRange.location,
                    effectiveRange: nil
                ) as? NSFont)
                XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.italic))
            case "u":
                XCTAssertEqual(
                    rendered.attribute(
                        .underlineStyle,
                        at: contentRange.location,
                        effectiveRange: nil
                    ) as? Int,
                    NSUnderlineStyle.single.rawValue
                )
            default:
                XCTFail("Unexpected formatting shortcut")
            }

            checkboxTextView.setSelectedRange(contentRange)
            XCTAssertTrue(panel.performKeyEquivalent(with: commandKeyEvent(
                keyCode: item.keyCode,
                characters: item.key
            )))
            XCTAssertEqual(checkboxTextView.sourceText, "Format me")
        }
    }

    func testCommandBoldAtCaretInsertsMarkdownPair() {
        controller.applyToCurrentPad("Start ", replacing: true)
        checkboxTextView.setSelectedRange(NSRange(location: 6, length: 0))

        XCTAssertTrue(panel.performKeyEquivalent(with: commandKeyEvent(
            keyCode: 11,
            characters: "b"
        )))
        XCTAssertEqual(checkboxTextView.sourceText, "Start ****")
        XCTAssertEqual(checkboxTextView.selectedRange(), NSRange(location: 8, length: 0))
    }

    func testFormattingShortcutAcceptsWholeLineSelectionWithTrailingNewline() {
        controller.applyToCurrentPad("Whole row\nNext", replacing: true)
        checkboxTextView.setSelectedRange(NSRange(location: 0, length: 10))

        XCTAssertTrue(panel.performKeyEquivalent(with: commandKeyEvent(
            keyCode: 11,
            characters: "b"
        )))
        XCTAssertEqual(checkboxTextView.sourceText, "**Whole row**\nNext")
    }

    func testFormattingShortcutsRejectSelectionsThatWouldBreakMarkdown() {
        for source in ["First\nSecond", "- [ ] Task"] {
            controller.applyToCurrentPad(source, replacing: true)
            checkboxTextView.setSelectedRange(NSRange(
                location: 0,
                length: checkboxTextView.attributedString().length
            ))

            XCTAssertFalse(panel.performKeyEquivalent(with: commandKeyEvent(
                keyCode: 11,
                characters: "b"
            )))
            XCTAssertEqual(checkboxTextView.sourceText, source)
        }
    }

    func testFormattingShortcutsRemoveAlternateMarkdownDelimiters() {
        let cases: [(source: String, content: String, keyCode: UInt16, key: String)] = [
            ("__Bold__", "Bold", 11, "b"),
            ("_Italic_", "Italic", 34, "i"),
        ]

        for item in cases {
            controller.applyToCurrentPad(item.source, replacing: true)
            let contentRange = (checkboxTextView.attributedString().string as NSString)
                .range(of: item.content)
            checkboxTextView.setSelectedRange(contentRange)

            XCTAssertTrue(panel.performKeyEquivalent(with: commandKeyEvent(
                keyCode: item.keyCode,
                characters: item.key
            )))
            XCTAssertEqual(checkboxTextView.sourceText, item.content)
        }
    }

    func testCompletingMarkdownDelimiterRefreshesLiveStyling() throws {
        let textView = try XCTUnwrap(controller.textView as? CheckboxTextView)
        controller.applyToCurrentPad("**live*", replacing: true)

        textView.replaceCharacters(
            in: NSRange(location: textView.attributedString().length, length: 0),
            withSourceText: "*"
        )

        let rendered = textView.attributedString()
        let liveRange = (rendered.string as NSString).range(of: "live")
        let font = try XCTUnwrap(rendered.attribute(
            .font,
            at: liveRange.location,
            effectiveRange: nil
        ) as? NSFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertEqual(textView.sourceText, "**live**")

        textView.replaceCharacters(
            in: NSRange(location: textView.attributedString().length - 1, length: 1),
            withSourceText: ""
        )
        let revealedFont = try XCTUnwrap(textView.attributedString().attribute(
            .font,
            at: 0,
            effectiveRange: nil
        ) as? NSFont)
        XCTAssertGreaterThan(revealedFont.pointSize, 1)
        XCTAssertEqual(textView.sourceText, "**live*")
    }

    func testMarkdownCodeSuppressesLinksAndParenthesizedURLsStayWhole() throws {
        let textView = try XCTUnwrap(controller.textView as? CheckboxTextView)
        let source = "`[literal](https://example.com)` [wiki](https://en.wikipedia.org/wiki/Foo_(bar))"

        controller.applyToCurrentPad(source, replacing: true)

        let rendered = textView.attributedString()
        let display = rendered.string as NSString
        let destinationRange = display.range(of: "https://en.wikipedia.org/wiki/Foo_(bar)")
        XCTAssertNil(rendered.attribute(
            .link,
            at: display.range(of: "literal").location,
            effectiveRange: nil
        ))
        XCTAssertEqual(
            rendered.attribute(
                .link,
                at: display.range(of: "wiki").location,
                effectiveRange: nil
            ) as? URL,
            URL(string: "https://en.wikipedia.org/wiki/Foo_(bar)")
        )
        let hiddenDestinationFont = try XCTUnwrap(rendered.attribute(
            .font,
            at: destinationRange.location,
            effectiveRange: nil
        ) as? NSFont)
        let hiddenDestinationColor = try XCTUnwrap(rendered.attribute(
            .foregroundColor,
            at: destinationRange.location,
            effectiveRange: nil
        ) as? NSColor)
        XCTAssertLessThan(hiddenDestinationFont.pointSize, 1)
        XCTAssertEqual(hiddenDestinationColor.alphaComponent, 0)
        let labelEnd = NSMaxRange(display.range(of: "wiki"))
        XCTAssertEqual(
            textView.selectionRangeBySkippingHiddenSyntax(
                NSRange(location: labelEnd + 1, length: 0),
                from: NSRange(location: labelEnd, length: 0)
            ),
            NSRange(location: display.length, length: 0)
        )
        XCTAssertEqual(
            textView.selectionRangeBySkippingHiddenSyntax(
                NSRange(location: display.length - 1, length: 0),
                from: NSRange(location: display.length, length: 0)
            ),
            NSRange(location: labelEnd, length: 0)
        )
        XCTAssertEqual(textView.sourceText, source)
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

    private func commandKeyEvent(keyCode: UInt16, characters: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
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
