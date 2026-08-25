import AppKit

enum MarkdownInlineStyle {
    case bold
    case italic
    case underline

    var markerPairs: [(opening: String, closing: String)] {
        switch self {
        case .bold: [("**", "**"), ("__", "__")]
        case .italic: [("*", "*"), ("_", "_")]
        case .underline: [("<u>", "</u>")]
        }
    }

    var markers: (opening: String, closing: String) {
        markerPairs[0]
    }
}

enum MarkdownStyling {
    static let hiddenSyntaxAttribute = NSAttributedString.Key(
        "BetterTotHiddenMarkdownSyntax"
    )
    private static let heading = try! NSRegularExpression(
        pattern: #"(?m)^(#{1,6})[\t ]+([^\r\n]+)$"#
    )
    private static let bold = try! NSRegularExpression(
        pattern: #"(?<!\*)\*\*(?=\S)(.+?)(?<=\S)\*\*(?!\*)"#
    )
    private static let alternateBold = try! NSRegularExpression(
        pattern: #"(?<!_)__(?=\S)(.+?)(?<=\S)__(?!_)"#
    )
    private static let italic = try! NSRegularExpression(
        pattern: #"(?<!\*)\*(?!\*)(?=\S)(.+?)(?<=\S)\*(?!\*)"#
    )
    private static let alternateItalic = try! NSRegularExpression(
        pattern: #"(?<!_)_(?!_)(?=\S)(.+?)(?<=\S)_(?!_)"#
    )
    private static let underline = try! NSRegularExpression(
        pattern: #"<u>(?=\S)(.+?)(?<=\S)</u>"#,
        options: [.caseInsensitive]
    )
    private static let code = try! NSRegularExpression(pattern: #"`([^`\r\n]+)`"#)
    private static let link = try! NSRegularExpression(
        pattern: #"\[([^\]\r\n]+)\]\((https?://(?:[^\s()]|\([^\s()]*\))+)\)"#,
        options: [.caseInsensitive]
    )

    static func apply(
        to text: NSMutableAttributedString,
        baseFont: NSFont,
        tintColor: NSColor
    ) {
        let fullRange = NSRange(location: 0, length: text.length)
        guard fullRange.length > 0 else { return }

        text.beginEditing()
        for attribute in [
            NSAttributedString.Key.backgroundColor,
            .underlineStyle,
            .link,
            hiddenSyntaxAttribute,
        ] {
            text.removeAttribute(attribute, range: fullRange)
        }
        text.addAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
        ], range: fullRange)

        applyEmphasis(
            bold,
            to: text,
            font: font(baseFont, trait: .boldFontMask),
            color: tintColor,
            markerWidth: 2
        )
        applyEmphasis(
            alternateBold,
            to: text,
            font: font(baseFont, trait: .boldFontMask),
            color: tintColor,
            markerWidth: 2
        )
        applyEmphasis(italic, to: text, font: font(baseFont, trait: .italicFontMask))
        applyEmphasis(
            alternateItalic,
            to: text,
            font: font(baseFont, trait: .italicFontMask)
        )
        applyUnderline(to: text)
        applyLinks(to: text)
        applyHeadings(to: text, baseFont: baseFont)
        applyCode(to: text, baseFont: baseFont)
        text.endEditing()
    }

    private static func applyUnderline(to text: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: text.length)
        for match in underline.matches(in: text.string, range: fullRange) {
            text.addAttribute(
                .underlineStyle,
                value: NSUnderlineStyle.single.rawValue,
                range: match.range(at: 1)
            )
            hide(NSRange(location: match.range.location, length: 3), in: text)
            hide(NSRange(location: NSMaxRange(match.range) - 4, length: 4), in: text)
        }
    }

    private static func applyEmphasis(
        _ expression: NSRegularExpression,
        to text: NSMutableAttributedString,
        font: NSFont,
        color: NSColor? = nil,
        markerWidth: Int = 1
    ) {
        let fullRange = NSRange(location: 0, length: text.length)
        for match in expression.matches(in: text.string, range: fullRange) {
            text.addAttribute(.font, value: font, range: match.range(at: 1))
            if let color {
                text.addAttribute(.foregroundColor, value: color, range: match.range(at: 1))
            }
            hideMarkers(in: text, match: match.range, width: markerWidth)
        }
    }

    private static func applyCode(to text: NSMutableAttributedString, baseFont: NSFont) {
        let fullRange = NSRange(location: 0, length: text.length)
        let codeFont = NSFont.monospacedSystemFont(
            ofSize: max(11, baseFont.pointSize * 0.94),
            weight: .regular
        )
        for match in code.matches(in: text.string, range: fullRange) {
            text.removeAttribute(.link, range: match.range)
            text.removeAttribute(.underlineStyle, range: match.range)
            text.removeAttribute(hiddenSyntaxAttribute, range: match.range)
            text.addAttributes([
                .font: codeFont,
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.separatorColor.withAlphaComponent(0.28),
            ], range: match.range)
            hideMarkers(in: text, match: match.range, width: 1)
        }
    }

    private static func applyLinks(to text: NSMutableAttributedString) {
        let fullRange = NSRange(location: 0, length: text.length)
        for match in link.matches(in: text.string, range: fullRange) {
            let destinationRange = match.range(at: 2)
            guard let destination = URL(string: (text.string as NSString).substring(
                with: destinationRange
            )) else { continue }
            text.addAttributes([
                .link: destination,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: match.range(at: 1))
            hideLinkSyntax(in: text, match: match)
        }
    }

    private static func applyHeadings(to text: NSMutableAttributedString, baseFont: NSFont) {
        let scales: [CGFloat] = [1.55, 1.4, 1.28, 1.18, 1.1, 1.05]
        let fullRange = NSRange(location: 0, length: text.length)
        for match in heading.matches(in: text.string, range: fullRange) {
            let level = min(6, match.range(at: 1).length)
            let headingFont = font(
                baseFont,
                trait: .boldFontMask,
                size: round(baseFont.pointSize * scales[level - 1])
            )
            text.addAttribute(.font, value: headingFont, range: match.range(at: 2))
            hide(
                NSRange(
                    location: match.range.location,
                    length: match.range(at: 2).location - match.range.location
                ),
                in: text
            )
        }
    }

    private static func hideMarkers(
        in text: NSMutableAttributedString,
        match: NSRange,
        width: Int
    ) {
        hide(
            NSRange(location: match.location, length: width),
            in: text
        )
        hide(
            NSRange(location: NSMaxRange(match) - width, length: width),
            in: text
        )
    }

    private static func hideLinkSyntax(
        in text: NSMutableAttributedString,
        match: NSTextCheckingResult
    ) {
        let labelRange = match.range(at: 1)
        let destinationRange = match.range(at: 2)
        hide(NSRange(location: match.range.location, length: 1), in: text)
        hide(NSRange(
            location: NSMaxRange(labelRange),
            length: destinationRange.location - NSMaxRange(labelRange)
        ), in: text)
        hide(destinationRange, in: text)
        hide(NSRange(
            location: NSMaxRange(destinationRange),
            length: NSMaxRange(match.range) - NSMaxRange(destinationRange)
        ), in: text)
    }

    private static func hide(_ range: NSRange, in text: NSMutableAttributedString) {
        text.addAttributes([
            .font: NSFont.systemFont(ofSize: 0.01),
            .foregroundColor: NSColor.clear,
            .backgroundColor: NSColor.clear,
            hiddenSyntaxAttribute: true,
        ], range: range)
    }

    private static func font(
        _ baseFont: NSFont,
        trait: NSFontTraitMask,
        size: CGFloat? = nil
    ) -> NSFont {
        let manager = NSFontManager.shared
        var converted = manager.convert(baseFont, toHaveTrait: trait)
        if manager.traits(of: converted).intersection(trait).isEmpty {
            converted = manager.convert(
                NSFont.systemFont(ofSize: baseFont.pointSize),
                toHaveTrait: trait
            )
        }
        guard let size else { return converted }
        return NSFont(descriptor: converted.fontDescriptor, size: size) ?? converted
    }
}
