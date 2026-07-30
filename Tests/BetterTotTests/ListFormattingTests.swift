import Foundation
import XCTest
@testable import BetterTot

final class ListFormattingTests: XCTestCase {
    func testBulletsSelectedLinesAndTogglesThemOff() {
        let added = ListFormatter.toggle(
            in: "alpha\nbeta",
            selection: NSRange(location: 0, length: 10),
            style: .bulleted
        )
        XCTAssertEqual(added.replacement, "• alpha\n• beta")
        XCTAssertEqual(added.selection, NSRange(location: 2, length: 12))

        let removed = ListFormatter.toggle(
            in: added.replacement,
            selection: added.selection,
            style: .bulleted
        )
        XCTAssertEqual(removed.replacement, "alpha\nbeta")
        XCTAssertEqual(removed.selection, NSRange(location: 0, length: 10))
    }

    func testNumberedListReplacesOtherMarkersAndPreservesIndentation() {
        let result = ListFormatter.toggle(
            in: "  - alpha\n  ☐ beta",
            selection: NSRange(location: 0, length: 18),
            style: .numbered
        )

        XCTAssertEqual(result.replacement, "  1. alpha\n  2. beta")
    }

    func testCaretAndEmojiOffsetsRemainUTF16Correct() {
        let text = "👩🏽‍💻 task"
        let end = (text as NSString).length
        let result = ListFormatter.toggle(
            in: text,
            selection: NSRange(location: end, length: 0),
            style: .bulleted
        )

        XCTAssertEqual(result.replacement, "• \(text)")
        XCTAssertEqual(result.selection, NSRange(location: end + 2, length: 0))
    }

    func testCheckboxListReplacesBulletsAndTogglesOff() {
        let added = ListFormatter.toggle(
            in: "• alpha\n• beta",
            selection: NSRange(location: 0, length: 14),
            style: .checkbox
        )
        XCTAssertEqual(added.replacement, "☐ alpha\n☐ beta")

        let removed = ListFormatter.toggle(
            in: added.replacement,
            selection: added.selection,
            style: .checkbox
        )
        XCTAssertEqual(removed.replacement, "alpha\nbeta")
    }
}
