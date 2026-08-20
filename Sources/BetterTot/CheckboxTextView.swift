import AppKit

enum AutomaticListKind {
    case bulleted
    case dash
    case numbered
    case checkbox
}

struct AutomaticListLine {
    let indentationLength: Int
    let markerLength: Int
    let clickableMarkerLength: Int
    let continuationMarker: String
    let normalizedMarker: String?
    let toggledMarker: String?
    let isEmpty: Bool
    let kind: AutomaticListKind

    var isCheckbox: Bool { toggledMarker != nil }
    var isChecked: Bool { normalizedMarker == "☑ " }

    static func parse(_ line: NSString) -> AutomaticListLine? {
        var indentationLength = 0
        while indentationLength < line.length {
            let character = line.character(at: indentationLength)
            guard character == 0x20 || character == 0x09 else { break }
            indentationLength += 1
        }

        let remainder = line.substring(from: indentationLength)
        let checkboxMarkers: [(String, String, String, String, Int)] = [
            ("☐ ", "☐ ", "☐ ", "☑ ", 1),
            ("☑ ", "☐ ", "☑ ", "☐ ", 1),
            ("- [ ] ", "☐ ", "☐ ", "☑ ", 6),
            ("- [x] ", "☐ ", "☑ ", "☐ ", 6),
            ("- [X] ", "☐ ", "☑ ", "☐ ", 6),
            ("⬜ ", "☐ ", "☐ ", "☑ ", 2),
            ("✅ ", "☐ ", "☑ ", "☐ ", 2),
        ]
        if let marker = checkboxMarkers.first(where: { remainder.hasPrefix($0.0) }) {
            let markerLength = (marker.0 as NSString).length
            let contentStart = indentationLength + markerLength
            let content = line.substring(from: contentStart)
            return AutomaticListLine(
                indentationLength: indentationLength,
                markerLength: markerLength,
                clickableMarkerLength: marker.4,
                continuationMarker: marker.1,
                normalizedMarker: marker.2,
                toggledMarker: marker.3,
                isEmpty: content.trimmingCharacters(in: .whitespaces).isEmpty,
                kind: .checkbox
            )
        }

        if remainder.hasPrefix("- ") {
            let content = line.substring(from: indentationLength + 2)
            return AutomaticListLine(
                indentationLength: indentationLength,
                markerLength: 2,
                clickableMarkerLength: 0,
                continuationMarker: "- ",
                normalizedMarker: nil,
                toggledMarker: nil,
                isEmpty: content.trimmingCharacters(in: .whitespaces).isEmpty,
                kind: .dash
            )
        }

        for marker in ["* ", "• "] where remainder.hasPrefix(marker) {
            let markerLength = (marker as NSString).length
            let content = line.substring(from: indentationLength + markerLength)
            return AutomaticListLine(
                indentationLength: indentationLength,
                markerLength: markerLength,
                clickableMarkerLength: 0,
                continuationMarker: "• ",
                normalizedMarker: nil,
                toggledMarker: nil,
                isEmpty: content.trimmingCharacters(in: .whitespaces).isEmpty,
                kind: .bulleted
            )
        }

        let remainderString = remainder as NSString
        var digitLength = 0
        while digitLength < remainderString.length {
            let character = remainderString.character(at: digitLength)
            guard (0x30...0x39).contains(character) else { break }
            digitLength += 1
        }
        guard digitLength > 0,
              digitLength + 1 < remainderString.length,
              remainderString.character(at: digitLength) == 0x2E,
              remainderString.character(at: digitLength + 1) == 0x20,
              let number = Int(remainderString.substring(to: digitLength)) else {
            return nil
        }

        let markerLength = digitLength + 2
        let content = line.substring(from: indentationLength + markerLength)
        return AutomaticListLine(
            indentationLength: indentationLength,
            markerLength: markerLength,
            clickableMarkerLength: 0,
            continuationMarker: "\(number + 1). ",
            normalizedMarker: nil,
            toggledMarker: nil,
            isEmpty: content.trimmingCharacters(in: .whitespaces).isEmpty,
            kind: .numbered
        )
    }
}

private struct CheckboxOffsetReplacement {
    let sourceRange: NSRange
    let displayRange: NSRange
}

struct CheckboxCoordinateMap {
    fileprivate let replacements: [CheckboxOffsetReplacement]

    func displayRange(forSourceRange sourceRange: NSRange) -> NSRange {
        let start = displayOffset(forSourceOffset: sourceRange.location)
        let end = displayOffset(forSourceOffset: NSMaxRange(sourceRange))
        return NSRange(location: start, length: max(0, end - start))
    }

    func sourceRange(forDisplayRange displayRange: NSRange) -> NSRange {
        let start = sourceOffset(forDisplayOffset: displayRange.location)
        let end = sourceOffset(forDisplayOffset: NSMaxRange(displayRange))
        return NSRange(location: start, length: max(0, end - start))
    }

    private func displayOffset(forSourceOffset offset: Int) -> Int {
        var delta = 0
        for replacement in replacements {
            let source = replacement.sourceRange
            let display = replacement.displayRange
            if offset < source.location { break }
            if offset <= NSMaxRange(source) {
                let relative = offset - source.location
                if relative == 0 { return display.location }
                if relative >= source.length { return NSMaxRange(display) }
                return display.location + min(1, display.length)
            }
            delta += display.length - source.length
        }
        return max(0, offset + delta)
    }

    private func sourceOffset(forDisplayOffset offset: Int) -> Int {
        var delta = 0
        for replacement in replacements {
            let source = replacement.sourceRange
            let display = replacement.displayRange
            if offset < display.location { break }
            if offset <= NSMaxRange(display) {
                let relative = offset - display.location
                if relative == 0 { return source.location }
                if relative >= display.length { return NSMaxRange(source) }
                return source.location + max(1, source.length - 1)
            }
            delta += source.length - display.length
        }
        return max(0, offset + delta)
    }
}

struct CheckboxTextProjection {
    let attributedString: NSAttributedString
    let canonicalSource: String
    let inputToDisplayMap: CheckboxCoordinateMap
}

struct CanonicalCheckboxText {
    let source: String
    let sourceRange: NSRange
}

final class CheckboxAttachmentCell: NSTextAttachmentCell {
    let isChecked: Bool
    var baseFont: NSFont
    var tintColor: NSColor {
        didSet { updateImage() }
    }

    init(isChecked: Bool, tintColor: NSColor, baseFont: NSFont) {
        self.isChecked = isChecked
        self.tintColor = tintColor
        self.baseFont = baseFont
        super.init(textCell: "")
        updateImage()
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(isChecked ? "Completed checkbox" : "Unchecked checkbox")
        setAccessibilityValue(isChecked)
    }

    required init(coder: NSCoder) {
        isChecked = false
        tintColor = .controlAccentColor
        baseFont = .systemFont(ofSize: 14)
        super.init(coder: coder)
        updateImage()
    }

    override var cellSize: NSSize {
        NSSize(width: boxSize + 4, height: boxSize + 4)
    }

    override func cellBaselineOffset() -> NSPoint {
        NSPoint(x: 0, y: -round(boxSize * 0.20) - 1)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let boxRect = NSRect(
            x: cellFrame.minX,
            y: cellFrame.midY - boxSize / 2,
            width: boxSize,
            height: boxSize
        )
        if isChecked {
            tintColor.setFill()
            NSBezierPath(roundedRect: boxRect, xRadius: 3, yRadius: 3).fill()
            checkmarkImage?.draw(in: boxRect.insetBy(dx: 3, dy: 3))
        } else {
            let lineWidth: CGFloat = 2
            let strokeRect = boxRect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
            let box = NSBezierPath(roundedRect: strokeRect, xRadius: 2, yRadius: 2)
            tintColor.setStroke()
            box.lineWidth = lineWidth
            box.stroke()
        }
    }

    private func updateImage() {
        image = nil
    }

    private var checkmarkImage: NSImage? {
        let configuration = NSImage.SymbolConfiguration(
            pointSize: boxSize * 0.66,
            weight: .bold
        )
            .applying(NSImage.SymbolConfiguration(paletteColors: [checkmarkColor]))
        return NSImage(
            systemSymbolName: "checkmark",
            accessibilityDescription: "Completed"
        )?.withSymbolConfiguration(configuration)
    }

    private var checkmarkColor: NSColor {
        guard let color = tintColor.usingColorSpace(.deviceRGB) else {
            return .black
        }
        let luminance = 0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent
        return luminance > 0.55 ? .black : .white
    }

    private var boxSize: CGFloat {
        min(32, max(14, round(baseFont.pointSize * 1.1)))
    }
}

private struct SerializedCheckboxText {
    let source: String
    let plainText: String
    let map: CheckboxCoordinateMap
}

final class CheckboxTextView: NSTextView {
    var onCheckboxActivation: ((Int) -> Void)?
    private var checkboxTintColor = NSColor.controlAccentColor
    private var editorBaseFont = NSFont.systemFont(ofSize: 14)
    private var isTrackingCheckboxGesture = false

    static func makeScrollable() -> (scrollView: NSScrollView, textView: CheckboxTextView) {
        let textView = CheckboxTextView(frame: .zero)
        textView.minSize = .zero
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return (scrollView, textView)
    }

    var sourceText: String {
        serializeCurrentText().source
    }

    var plainText: String {
        serializeCurrentText().plainText
    }

    var visibleText: String {
        let text = attributedString()
        let string = text.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        var result = ""
        text.enumerateAttributes(in: fullRange) { attributes, range, _ in
            if attributes[MarkdownStyling.hiddenSyntaxAttribute] != nil { return }
            if let attachment = attributes[.attachment] as? NSTextAttachment,
               let cell = attachment.attachmentCell as? CheckboxAttachmentCell {
                result += cell.isChecked ? "☑" : "☐"
            } else {
                result += string.substring(with: range)
            }
        }
        return result
    }

    func sourceRange(forDisplayRange range: NSRange) -> NSRange {
        serializeCurrentText().map.sourceRange(forDisplayRange: range)
    }

    func displayRange(forSourceRange range: NSRange) -> NSRange {
        serializeCurrentText().map.displayRange(forSourceRange: range)
    }

    func selectionRangeBySkippingHiddenSyntax(
        _ proposed: NSRange,
        from previous: NSRange
    ) -> NSRange {
        guard proposed.length == 0,
              previous.length == 0,
              proposed.location != previous.location,
              proposed.location < attributedString().length,
              let hiddenRange = hiddenSyntaxRange(at: proposed.location) else {
            return proposed
        }
        return NSRange(
            location: proposed.location > previous.location
                ? NSMaxRange(hiddenRange)
                : hiddenRange.location,
            length: 0
        )
    }

    func sourceSafeRange(forVisibleSelection selection: NSRange) -> NSRange {
        guard selection.location != NSNotFound, selection.length > 0 else { return selection }
        let lowerBound = selection.location
        let upperBound = NSMaxRange(selection)
        let leading = lowerBound > 0 ? hiddenSyntaxRange(at: lowerBound - 1) : nil
        let trailing = upperBound < attributedString().length
            ? hiddenSyntaxRange(at: upperBound)
            : nil

        if let leading,
           NSMaxRange(leading) == lowerBound,
           let trailing,
           trailing.location == upperBound {
            return NSRange(
                location: leading.location,
                length: NSMaxRange(trailing) - leading.location
            )
        }

        let string = attributedString().string as NSString
        let lineRange = string.lineRange(for: selection)
        var lineContentEnd = NSMaxRange(lineRange)
        while lineContentEnd > lineRange.location,
              [0x0A, 0x0D].contains(string.character(at: lineContentEnd - 1)) {
            lineContentEnd -= 1
        }
        if let leading,
           leading.location == lineRange.location,
           NSMaxRange(leading) == lowerBound,
           upperBound == lineContentEnd {
            return NSRange(
                location: leading.location,
                length: upperBound - leading.location
            )
        }
        return selection
    }

    @discardableResult
    func setSourceText(
        _ source: String,
        baseFont: NSFont,
        tintColor: NSColor
    ) -> CheckboxTextProjection {
        checkboxTintColor = tintColor
        editorBaseFont = baseFont
        let projection = Self.project(source, baseFont: baseFont, tintColor: tintColor)
        textStorage?.setAttributedString(projection.attributedString)
        typingAttributes[.font] = baseFont
        typingAttributes[.foregroundColor] = NSColor.labelColor
        typingAttributes[.paragraphStyle] = Self.paragraphStyle(for: baseFont)
        window?.invalidateCursorRects(for: self)
        return projection
    }

    func attributedPresentation(for source: String) -> NSAttributedString {
        Self.project(
            source,
            baseFont: editorBaseFont,
            tintColor: checkboxTintColor
        ).attributedString
    }

    func updateCheckboxPresentation(baseFont: NSFont, tintColor: NSColor) {
        checkboxTintColor = tintColor
        editorBaseFont = baseFont
        typingAttributes[.font] = baseFont
        typingAttributes[.foregroundColor] = NSColor.labelColor
        let paragraphStyle = Self.paragraphStyle(for: baseFont)
        typingAttributes[.paragraphStyle] = paragraphStyle
        let fullRange = NSRange(location: 0, length: attributedString().length)
        if fullRange.length > 0 {
            textStorage?.addAttributes(
                [
                    .font: baseFont,
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: paragraphStyle,
                ],
                range: fullRange
            )
        }
        textStorage?.enumerateAttribute(
            .attachment,
            in: fullRange
        ) { value, _, _ in
            guard let attachment = value as? NSTextAttachment,
                  let cell = attachment.attachmentCell as? CheckboxAttachmentCell else {
                return
            }
            cell.baseFont = baseFont
            cell.tintColor = tintColor
        }
        applyCheckboxHangingIndents(baseFont: baseFont)
        if let textStorage {
            MarkdownStyling.apply(
                to: textStorage,
                baseFont: baseFont,
                tintColor: tintColor
            )
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    static func canonicalize(_ source: String, sourceRange: NSRange) -> CanonicalCheckboxText {
        let sourceLength = (source as NSString).length
        let location = min(max(0, sourceRange.location), sourceLength)
        let clampedRange = NSRange(
            location: location,
            length: min(max(0, sourceRange.length), sourceLength - location)
        )
        let projection = project(
            source,
            baseFont: .systemFont(ofSize: 14),
            tintColor: .controlAccentColor
        )
        let displayRange = projection.inputToDisplayMap.displayRange(
            forSourceRange: clampedRange
        )
        let canonicalMap = serialize(projection.attributedString).map
        return CanonicalCheckboxText(
            source: projection.canonicalSource,
            sourceRange: canonicalMap.sourceRange(forDisplayRange: displayRange)
        )
    }

    func fitDocument(to scrollView: NSScrollView) {
        let contentSize = scrollView.contentSize
        frame = NSRect(origin: .zero, size: contentSize)
        minSize = NSSize(width: 0, height: contentSize.height)
        updateTextContainerWidth(for: contentSize.width)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTextContainerWidth(for: newSize.width)
    }

    private func updateTextContainerWidth(for viewWidth: CGFloat) {
        textContainer?.containerSize = NSSize(
            width: max(0, viewWidth - (textContainerInset.width * 2)),
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let layoutManager, let textContainer else { return }
        let fullRange = NSRange(location: 0, length: attributedString().length)
        textStorage?.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard value is NSTextAttachment else { return }
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: range,
                actualCharacterRange: nil
            )
            let bounds = layoutManager.boundingRect(
                forGlyphRange: glyphRange,
                in: textContainer
            ).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if checkboxCharacterIndex(atWindowPoint: event.locationInWindow) != nil {
            NSCursor.pointingHand.set()
        } else {
            super.cursorUpdate(with: event)
        }
    }

    override func didChangeText() {
        if let textStorage {
            MarkdownStyling.apply(
                to: textStorage,
                baseFont: editorBaseFont,
                tintColor: checkboxTintColor
            )
        }
        super.didChangeText()
        window?.invalidateCursorRects(for: self)
    }

    override func mouseDown(with event: NSEvent) {
        guard let characterIndex = checkboxCharacterIndex(
            atWindowPoint: event.locationInWindow
        ) else {
            isTrackingCheckboxGesture = false
            super.mouseDown(with: event)
            return
        }

        isTrackingCheckboxGesture = true
        if event.clickCount == 1 {
            onCheckboxActivation?(characterIndex)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !isTrackingCheckboxGesture else { return }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isTrackingCheckboxGesture else {
            super.mouseUp(with: event)
            return
        }
        isTrackingCheckboxGesture = false
    }

    override func copy(_ sender: Any?) {
        let selection = sourceSafeRange(forVisibleSelection: selectedRange())
        guard selection.location != NSNotFound, selection.length > 0 else { return }
        let selected = attributedString().attributedSubstring(from: selection)
        let serialized = Self.serialize(selected)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(serialized.source, forType: .string)
    }

    override func cut(_ sender: Any?) {
        let selection = sourceSafeRange(forVisibleSelection: selectedRange())
        guard selection.location != NSNotFound, selection.length > 0 else { return }
        setSelectedRange(selection)
        copy(sender)
        replaceCharacters(in: selection, withSourceText: "")
    }

    override func paste(_ sender: Any?) {
        guard let pasted = NSPasteboard.general.string(forType: .string) else { return }
        replaceCharacters(in: selectedRange(), withSourceText: pasted)
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
        guard let inserted = Self.stringValue(of: insertString),
              !inserted.contains(where: \.isNewline),
              range.location != NSNotFound,
              NSMaxRange(range) <= attributedString().length,
              let conversion = automaticListLineConversion(
                inserting: inserted,
                replacing: range
              ) else {
            super.insertText(insertString, replacementRange: replacementRange)
            return
        }

        super.insertText(
            conversion.projection.attributedString,
            replacementRange: conversion.lineRange
        )
        setSelectedRange(NSRange(location: conversion.caretLocation, length: 0))
    }

    func replaceCharacters(in range: NSRange, withSourceText source: String) {
        let replacement = attributedPresentation(for: source)
        guard shouldChangeText(in: range, replacementString: replacement.string) else { return }
        textStorage?.replaceCharacters(in: range, with: replacement)
        didChangeText()
        setSelectedRange(NSRange(
            location: range.location + replacement.length,
            length: 0
        ))
    }

    private static func project(
        _ source: String,
        baseFont: NSFont,
        tintColor: NSColor
    ) -> CheckboxTextProjection {
        let input = source as NSString
        let output = NSMutableAttributedString()
        var canonicalSource = ""
        var inputReplacements: [CheckboxOffsetReplacement] = []
        var inputLocation = 0

        while inputLocation < input.length {
            let lineRange = input.lineRange(for: NSRange(location: inputLocation, length: 0))
            let rawLine = input.substring(with: lineRange) as NSString
            var contentLength = rawLine.length
            while contentLength > 0,
                  [0x0A, 0x0D].contains(rawLine.character(at: contentLength - 1)) {
                contentLength -= 1
            }
            let line = rawLine.substring(to: contentLength) as NSString
            let lineEnding = rawLine.substring(from: contentLength)

            if let list = AutomaticListLine.parse(line), list.isCheckbox {
                let indentation = line.substring(to: list.indentationLength)
                let content = line.substring(
                    from: list.indentationLength + list.markerLength
                )
                let cell = CheckboxAttachmentCell(
                    isChecked: list.isChecked,
                    tintColor: tintColor,
                    baseFont: baseFont
                )
                let hangingIndent = renderedWidth(of: indentation, font: baseFont)
                    + cell.cellSize.width
                    + renderedWidth(of: " ", font: baseFont)
                let style = paragraphStyle(
                    for: baseFont,
                    hangingIndent: hangingIndent
                )
                let displayMarkerLocation = output.length + (indentation as NSString).length
                append(indentation, to: output, font: baseFont, paragraphStyle: style)
                output.append(attachmentString(
                    cell: cell,
                    paragraphStyle: style
                ))
                append(" ", to: output, font: baseFont, paragraphStyle: style)
                append(
                    content + lineEnding,
                    to: output,
                    font: baseFont,
                    paragraphStyle: style
                )

                let markdownMarker = list.isChecked ? "- [x] " : "- [ ] "
                canonicalSource += indentation + markdownMarker + content + lineEnding
                inputReplacements.append(CheckboxOffsetReplacement(
                    sourceRange: NSRange(
                        location: lineRange.location + list.indentationLength,
                        length: list.markerLength
                    ),
                    displayRange: NSRange(location: displayMarkerLocation, length: 2)
                ))
            } else if let list = AutomaticListLine.parse(line),
                      list.kind == .bulleted {
                let indentation = line.substring(to: list.indentationLength)
                let content = line.substring(
                    from: list.indentationLength + list.markerLength
                )
                append(indentation + "• " + content + lineEnding, to: output, font: baseFont)
                canonicalSource += indentation + "* " + content + lineEnding
            } else {
                let raw = rawLine as String
                append(raw, to: output, font: baseFont)
                canonicalSource += raw
            }
            inputLocation = NSMaxRange(lineRange)
        }

        MarkdownStyling.apply(to: output, baseFont: baseFont, tintColor: tintColor)
        return CheckboxTextProjection(
            attributedString: output,
            canonicalSource: canonicalSource,
            inputToDisplayMap: CheckboxCoordinateMap(replacements: inputReplacements)
        )
    }

    private static func append(
        _ string: String,
        to output: NSMutableAttributedString,
        font: NSFont,
        paragraphStyle: NSParagraphStyle? = nil
    ) {
        output.append(NSAttributedString(
            string: string,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle ?? Self.paragraphStyle(for: font),
            ]
        ))
    }

    private static func attachmentString(
        cell: CheckboxAttachmentCell,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.attachmentCell = cell
        let attributed = NSMutableAttributedString(attachment: attachment)
        attributed.addAttribute(
            .paragraphStyle,
            value: paragraphStyle,
            range: NSRange(location: 0, length: attributed.length)
        )
        return attributed
    }

    private static func paragraphStyle(
        for font: NSFont,
        hangingIndent: CGFloat = 0
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byWordWrapping
        style.lineSpacing = max(3, round(font.pointSize * 0.28))
        style.firstLineHeadIndent = 0
        style.headIndent = ceil(hangingIndent)
        return style
    }

    private static func renderedWidth(of string: String, font: NSFont) -> CGFloat {
        (string as NSString).size(withAttributes: [.font: font]).width
    }

    private func applyCheckboxHangingIndents(baseFont: NSFont) {
        guard let textStorage else { return }
        let display = textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var updates: [(range: NSRange, style: NSParagraphStyle)] = []
        textStorage.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  let cell = attachment.attachmentCell as? CheckboxAttachmentCell else {
                return
            }
            let lineRange = display.lineRange(
                for: NSRange(location: range.location, length: 0)
            )
            let indentationRange = NSRange(
                location: lineRange.location,
                length: range.location - lineRange.location
            )
            let indentation = display.substring(with: indentationRange)
            let hangingIndent = Self.renderedWidth(of: indentation, font: baseFont)
                + cell.cellSize.width
                + Self.renderedWidth(of: " ", font: baseFont)
            updates.append((
                lineRange,
                Self.paragraphStyle(for: baseFont, hangingIndent: hangingIndent)
            ))
        }
        for update in updates {
            textStorage.addAttribute(
                .paragraphStyle,
                value: update.style,
                range: update.range
            )
        }
    }

    private func automaticListLineConversion(
        inserting inserted: String,
        replacing range: NSRange
    ) -> (lineRange: NSRange, projection: CheckboxTextProjection, caretLocation: Int)? {
        let display = attributedString()
        let displayString = display.string as NSString
        let lineRange = displayString.lineRange(
            for: NSRange(location: range.location, length: 0)
        )
        guard NSMaxRange(range) <= NSMaxRange(lineRange) else {
            return nil
        }
        let currentLine = display.attributedSubstring(from: lineRange)
        guard !currentLine.containsCheckboxAttachment else {
            return nil
        }

        let localRange = NSRange(
            location: range.location - lineRange.location,
            length: range.length
        )
        let line = displayString.substring(with: lineRange) as NSString
        let candidate = line.replacingCharacters(in: localRange, with: inserted)
        let projection = Self.project(
            candidate,
            baseFont: editorBaseFont,
            tintColor: checkboxTintColor
        )
        guard projection.attributedString.containsCheckboxAttachment
                || projection.attributedString.string != candidate else {
            return nil
        }

        let sourceCaret = localRange.location + (inserted as NSString).length
        let displayCaret = projection.inputToDisplayMap.displayRange(
            forSourceRange: NSRange(location: sourceCaret, length: 0)
        ).location
        return (
            lineRange,
            projection,
            lineRange.location + displayCaret
        )
    }

    private static func stringValue(of value: Any) -> String? {
        if let string = value as? String { return string }
        if let attributed = value as? NSAttributedString { return attributed.string }
        return nil
    }

    private func hiddenSyntaxRange(at characterIndex: Int) -> NSRange? {
        let text = attributedString()
        guard characterIndex >= 0, characterIndex < text.length else { return nil }
        var range = NSRange()
        guard text.attribute(
            MarkdownStyling.hiddenSyntaxAttribute,
            at: characterIndex,
            longestEffectiveRange: &range,
            in: NSRange(location: 0, length: text.length)
        ) != nil else { return nil }
        return range
    }

    private func checkboxCharacterIndex(atWindowPoint windowPoint: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, layoutManager.numberOfGlyphs > 0 else {
            return nil
        }
        let localPoint = convert(windowPoint, from: nil)
        let containerPoint = NSPoint(
            x: localPoint.x - textContainerOrigin.x,
            y: localPoint.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(
            for: containerPoint,
            in: textContainer,
            fractionOfDistanceThroughGlyph: nil
        )
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }

        let characterIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard characterIndex < attributedString().length,
              let attachment = attributedString().attribute(
                .attachment,
                at: characterIndex,
                effectiveRange: nil
              ) as? NSTextAttachment,
              attachment.attachmentCell is CheckboxAttachmentCell else {
            return nil
        }

        let glyphBounds = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        ).offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        return glyphBounds.contains(localPoint) ? characterIndex : nil
    }

    private func serializeCurrentText() -> SerializedCheckboxText {
        Self.serialize(attributedString())
    }

    private static func serialize(_ attributed: NSAttributedString) -> SerializedCheckboxText {
        let display = attributed.string as NSString
        let fullRange = NSRange(location: 0, length: attributed.length)
        var attachments: [(range: NSRange, cell: CheckboxAttachmentCell)] = []
        attributed.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  let cell = attachment.attachmentCell as? CheckboxAttachmentCell else {
                return
            }
            attachments.append((range, cell))
        }

        var source = ""
        var plainText = ""
        var sourceLocation = 0
        var cursor = 0
        var replacements: [CheckboxOffsetReplacement] = []
        for item in attachments {
            guard item.range.location >= cursor else { continue }
            let prefixRange = NSRange(
                location: cursor,
                length: item.range.location - cursor
            )
            let prefix = display.substring(with: prefixRange)
            source += prefix
            plainText += prefix
            sourceLocation += prefixRange.length

            var displayMarkerLength = item.range.length
            let afterAttachment = NSMaxRange(item.range)
            if afterAttachment < display.length,
               display.character(at: afterAttachment) == 0x20 {
                displayMarkerLength += 1
            }

            let markdownMarker = item.cell.isChecked ? "- [x] " : "- [ ] "
            let unicodeMarker = item.cell.isChecked ? "☑" : "☐"
            source += markdownMarker
            plainText += unicodeMarker
            if displayMarkerLength > item.range.length {
                plainText += " "
            }
            replacements.append(CheckboxOffsetReplacement(
                sourceRange: NSRange(
                    location: sourceLocation,
                    length: (markdownMarker as NSString).length
                ),
                displayRange: NSRange(
                    location: item.range.location,
                    length: displayMarkerLength
                )
            ))
            sourceLocation += (markdownMarker as NSString).length
            cursor = item.range.location + displayMarkerLength
        }

        if cursor < display.length {
            let suffix = display.substring(from: cursor)
            source += suffix
            plainText += suffix
        }
        return SerializedCheckboxText(
            source: markdownBullets(in: source),
            plainText: plainText,
            map: CheckboxCoordinateMap(replacements: replacements)
        )
    }

    private static func markdownBullets(in text: String) -> String {
        let input = text as NSString
        let output = NSMutableString()
        var location = 0
        while location < input.length {
            let lineRange = input.lineRange(for: NSRange(location: location, length: 0))
            let rawLine = input.substring(with: lineRange) as NSString
            var contentLength = rawLine.length
            while contentLength > 0,
                  [0x0A, 0x0D].contains(rawLine.character(at: contentLength - 1)) {
                contentLength -= 1
            }
            let line = rawLine.substring(to: contentLength) as NSString
            let lineEnding = rawLine.substring(from: contentLength)
            if let list = AutomaticListLine.parse(line), list.kind == .bulleted {
                let indentation = line.substring(to: list.indentationLength)
                let content = line.substring(
                    from: list.indentationLength + list.markerLength
                )
                output.append(indentation + "* " + content + lineEnding)
            } else {
                output.append(rawLine as String)
            }
            location = NSMaxRange(lineRange)
        }
        return output as String
    }
}

private extension NSAttributedString {
    var containsCheckboxAttachment: Bool {
        var found = false
        enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: length),
            options: [.longestEffectiveRangeNotRequired]
        ) { value, _, stop in
            guard let attachment = value as? NSTextAttachment,
                  attachment.attachmentCell is CheckboxAttachmentCell else {
                return
            }
            found = true
            stop.pointee = true
        }
        return found
    }
}
