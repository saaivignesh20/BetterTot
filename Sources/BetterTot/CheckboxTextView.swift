import AppKit

struct AutomaticListLine {
    let indentationLength: Int
    let markerLength: Int
    let clickableMarkerLength: Int
    let continuationMarker: String
    let normalizedMarker: String?
    let toggledMarker: String?
    let isEmpty: Bool

    static func parse(_ line: NSString) -> AutomaticListLine? {
        var indentationLength = 0
        while indentationLength < line.length {
            let character = line.character(at: indentationLength)
            guard character == 0x20 || character == 0x09 else { break }
            indentationLength += 1
        }

        let remainder = line.substring(from: indentationLength)
        let markers = [
            ("☐ ", "☐ ", "☐ ", "☑ ", 1),
            ("☑ ", "☐ ", "☑ ", "☐ ", 1),
            ("- [ ] ", "☐ ", "☐ ", "☑ ", 6),
            ("- [x] ", "☐ ", "☑ ", "☐ ", 6),
            ("- [X] ", "☐ ", "☑ ", "☐ ", 6),
            ("- ", "- ", nil, nil, 0),
            ("* ", "* ", nil, nil, 0),
        ]
        guard let marker = markers.first(where: { remainder.hasPrefix($0.0) }) else {
            return nil
        }

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
            isEmpty: content.trimmingCharacters(in: .whitespaces).isEmpty
        )
    }
}

final class CheckboxTextView: NSTextView {
    var onCheckboxClickAtCharacter: ((Int) -> Bool)?
    private var pendingCheckboxCharacter: Int?
    private var pendingMouseDownPoint: NSPoint?

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

    func fitDocument(to scrollView: NSScrollView) {
        let contentSize = scrollView.contentSize
        frame = NSRect(origin: .zero, size: contentSize)
        minSize = NSSize(width: 0, height: contentSize.height)
        textContainer?.containerSize = NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        )
    }

    override func mouseDown(with event: NSEvent) {
        pendingCheckboxCharacter = nil
        pendingMouseDownPoint = nil
        let selectionModifiers: NSEvent.ModifierFlags = [.shift, .command, .option, .control]
        if event.clickCount == 1,
           event.modifierFlags.intersection(selectionModifiers).isEmpty {
            pendingCheckboxCharacter = characterIndex(at: event.locationInWindow)
            pendingMouseDownPoint = event.locationInWindow
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        if !isWithinClickTolerance(event.locationInWindow) {
            pendingCheckboxCharacter = nil
            pendingMouseDownPoint = nil
        }
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let pendingCharacter = pendingCheckboxCharacter
        let isClick = isWithinClickTolerance(event.locationInWindow)
        pendingCheckboxCharacter = nil
        pendingMouseDownPoint = nil
        super.mouseUp(with: event)
        guard let pendingCharacter, isClick else { return }
        _ = onCheckboxClickAtCharacter?(pendingCharacter)
    }

    private func isWithinClickTolerance(_ point: NSPoint) -> Bool {
        guard let start = pendingMouseDownPoint else { return false }
        let deltaX = point.x - start.x
        let deltaY = point.y - start.y
        return deltaX * deltaX + deltaY * deltaY <= 16
    }

    private func characterIndex(at windowPoint: NSPoint) -> Int? {
        guard let layoutManager, let textContainer, layoutManager.numberOfGlyphs > 0 else {
            return nil
        }
        let localPoint = convert(windowPoint, from: nil)
        let containerPoint = NSPoint(
            x: localPoint.x - textContainerOrigin.x,
            y: localPoint.y - textContainerOrigin.y
        )
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        guard NSLocationInRange(glyphIndex, glyphRange) else { return nil }
        let glyphBounds = layoutManager.boundingRect(
            forGlyphRange: NSRange(location: glyphIndex, length: 1),
            in: textContainer
        ).insetBy(dx: -2, dy: -2)
        guard glyphBounds.contains(containerPoint) else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyphIndex)
    }
}
