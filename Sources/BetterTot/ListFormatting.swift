import Foundation

enum EditorListStyle {
    case bulleted
    case numbered
    case checkbox

    var kind: AutomaticListKind {
        switch self {
        case .bulleted: .bulleted
        case .numbered: .numbered
        case .checkbox: .checkbox
        }
    }

    func marker(position: Int) -> String {
        switch self {
        case .bulleted: "• "
        case .numbered: "\(position). "
        case .checkbox: "☐ "
        }
    }
}

struct ListFormattingResult {
    let replacementRange: NSRange
    let replacement: String
    let selection: NSRange
}

enum ListFormatter {
    private struct Line {
        let contentRange: NSRange
        let list: AutomaticListLine?
    }

    private struct Edit {
        let range: NSRange
        let replacement: String
    }

    static func toggle(
        in text: String,
        selection requestedSelection: NSRange,
        style: EditorListStyle
    ) -> ListFormattingResult {
        let source = text as NSString
        let selection = clamped(requestedSelection, toLength: source.length)
        let targetRange = selectedLineRange(in: source, selection: selection)
        let lines = selectedLines(in: source, range: targetRange)
        let removesMarkers = lines.allSatisfy { $0.list?.kind == style.kind }

        let edits = lines.enumerated().map { offset, line in
            let indentationLength = line.list?.indentationLength
                ?? leadingWhitespaceLength(in: source, range: line.contentRange)
            let markerLength = line.list?.markerLength ?? 0
            return Edit(
                range: NSRange(
                    location: line.contentRange.location + indentationLength,
                    length: markerLength
                ),
                replacement: removesMarkers ? "" : style.marker(position: offset + 1)
            )
        }

        let replacement = NSMutableString(
            string: source.substring(with: targetRange)
        )
        for edit in edits.reversed() {
            replacement.replaceCharacters(
                in: NSRange(
                    location: edit.range.location - targetRange.location,
                    length: edit.range.length
                ),
                with: edit.replacement
            )
        }

        return ListFormattingResult(
            replacementRange: targetRange,
            replacement: replacement as String,
            selection: NSRange(
                location: mapped(selection.location, through: edits),
                length: mapped(NSMaxRange(selection), through: edits)
                    - mapped(selection.location, through: edits)
            )
        )
    }

    private static func clamped(_ range: NSRange, toLength length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(
            location: location,
            length: min(max(0, range.length), length - location)
        )
    }

    private static func selectedLineRange(
        in source: NSString,
        selection: NSRange
    ) -> NSRange {
        let start = lineStart(in: source, at: selection.location)
        let selectionEnd = NSMaxRange(selection)
        let endProbe = selection.length > 0 ? max(selection.location, selectionEnd - 1) : selectionEnd
        let endStart = lineStart(in: source, at: endProbe)
        return NSRange(
            location: start,
            length: lineEnd(in: source, from: endStart) - start
        )
    }

    private static func selectedLines(in source: NSString, range: NSRange) -> [Line] {
        var lines: [Line] = []
        var location = range.location
        repeat {
            let end = lineEnd(in: source, from: location)
            var contentEnd = end
            while contentEnd > location {
                let character = source.character(at: contentEnd - 1)
                guard character == 0x0A || character == 0x0D else { break }
                contentEnd -= 1
            }
            let contentRange = NSRange(location: location, length: contentEnd - location)
            let content = source.substring(with: contentRange) as NSString
            lines.append(Line(
                contentRange: contentRange,
                list: AutomaticListLine.parse(content)
            ))
            location = end
        } while location < NSMaxRange(range)
        return lines
    }

    private static func lineStart(in source: NSString, at requestedLocation: Int) -> Int {
        var location = min(max(0, requestedLocation), source.length)
        while location > 0 {
            let previous = source.character(at: location - 1)
            if previous == 0x0A || previous == 0x0D { break }
            location -= 1
        }
        return location
    }

    private static func lineEnd(in source: NSString, from start: Int) -> Int {
        var location = start
        while location < source.length {
            let character = source.character(at: location)
            location += 1
            if character == 0x0A {
                break
            }
            if character == 0x0D {
                if location < source.length, source.character(at: location) == 0x0A {
                    location += 1
                }
                break
            }
        }
        return location
    }

    private static func leadingWhitespaceLength(in source: NSString, range: NSRange) -> Int {
        var length = 0
        while length < range.length {
            let character = source.character(at: range.location + length)
            guard character == 0x20 || character == 0x09 else { break }
            length += 1
        }
        return length
    }

    private static func mapped(_ offset: Int, through edits: [Edit]) -> Int {
        var delta = 0
        for edit in edits {
            if offset < edit.range.location { break }
            if offset <= NSMaxRange(edit.range) {
                return edit.range.location + delta + (edit.replacement as NSString).length
            }
            delta += (edit.replacement as NSString).length - edit.range.length
        }
        return offset + delta
    }
}
