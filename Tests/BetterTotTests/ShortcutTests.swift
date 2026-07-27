import AppKit
import Carbon.HIToolbox
import XCTest
@testable import BetterTot

final class ShortcutTests: XCTestCase {
    func testValidationRequiresRealModifierOrFunctionKey() {
        let cmd = UInt32(cmdKey), opt = UInt32(optionKey)
        let ctrl = UInt32(controlKey), shift = UInt32(shiftKey)
        XCTAssertFalse(Shortcut.isValid(keyCode: 0, carbonModifiers: 0), "bare letter is typing")
        XCTAssertFalse(Shortcut.isValid(keyCode: 0, carbonModifiers: shift), "shift alone is typing")
        XCTAssertTrue(Shortcut.isValid(keyCode: 0, carbonModifiers: cmd))
        XCTAssertTrue(Shortcut.isValid(keyCode: 49, carbonModifiers: opt | cmd))
        XCTAssertTrue(Shortcut.isValid(keyCode: 0, carbonModifiers: ctrl))
        XCTAssertTrue(Shortcut.isValid(keyCode: 96, carbonModifiers: 0), "F5 may stand alone")
        XCTAssertTrue(Shortcut.isValid(
            keyCode: Shortcut.defaultShortcut.keyCode,
            carbonModifiers: Shortcut.defaultShortcut.carbonModifiers),
            "the shipped default must be valid")
    }

    func testModifierSymbolsUseStandardOrder() {
        let all = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        XCTAssertEqual(Shortcut.modifierSymbols(all), "⌃⌥⇧⌘")
        XCTAssertEqual(Shortcut.modifierSymbols(UInt32(optionKey | cmdKey)), "⌥⌘")
        XCTAssertEqual(Shortcut.modifierSymbols(0), "")
    }

    func testKeyNamesForSpecialAndOrdinaryKeys() {
        XCTAssertEqual(Shortcut.keyName(keyCode: 49, fallback: " "), "Space")
        XCTAssertEqual(Shortcut.keyName(keyCode: 36, fallback: "\r"), "↩")
        XCTAssertEqual(Shortcut.keyName(keyCode: 123, fallback: nil), "←")
        XCTAssertEqual(Shortcut.keyName(keyCode: 96, fallback: nil), "F5")
        XCTAssertEqual(Shortcut.keyName(keyCode: 0, fallback: "a"), "A")
        XCTAssertEqual(Shortcut.keyName(keyCode: 44, fallback: "/"), "/")
        XCTAssertEqual(Shortcut.keyName(keyCode: 999, fallback: nil), "Key 999",
                       "unknown keys still render something")
    }

    func testShortcutCodableRoundTrip() throws {
        let original = Shortcut(keyCode: 3, carbonModifiers: UInt32(cmdKey | shiftKey), display: "⇧⌘F")
        let decoded = try JSONDecoder().decode(
            Shortcut.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testCarbonServiceRegisterUnregisterLifecycle() throws {
        let service = CarbonGlobalShortcutService(onPress: {})
        // F13/F14 with ⌥⌘: valid and very unlikely to be claimed by the system.
        let chord = Shortcut(keyCode: 105, carbonModifiers: UInt32(optionKey | cmdKey), display: "⌥⌘F13")
        try service.register(chord)
        XCTAssertEqual(service.currentShortcut, chord)
        service.unregister()
        XCTAssertNil(service.currentShortcut)
    }

    // The contract that matters: a FAILED re-registration must not leave a
    // stale shortcut behind (the caller restores the old one explicitly).
    func testFailedReregistrationLeavesNoStaleShortcut() throws {
        let contested = Shortcut(keyCode: 107, carbonModifiers: UInt32(optionKey | cmdKey), display: "⌥⌘F14")
        let holder = CarbonGlobalShortcutService(onPress: {})
        try holder.register(contested)
        defer { holder.unregister() }

        let service = CarbonGlobalShortcutService(onPress: {})
        let owned = Shortcut(keyCode: 113, carbonModifiers: UInt32(optionKey | cmdKey), display: "⌥⌘F15")
        try service.register(owned)
        XCTAssertEqual(service.currentShortcut, owned)

        // Carbon rejects a duplicate in-process registration; if this platform
        // ever allows it the test is honest about not having run.
        do {
            try service.register(contested)
            throw XCTSkip("Carbon allowed a duplicate registration; failure path not exercised")
        } catch is ShortcutError {
            XCTAssertNil(service.currentShortcut,
                         "a failed re-registration must not leave the previous shortcut set")
        }
    }

    func testLoadShortcutRejectsCorruptAndInvalidPersistedData() throws {
        let defaults = UserDefaults.standard
        let key = SettingsKeys.globalShortcut
        let original = defaults.data(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
        }

        defaults.removeObject(forKey: key)
        XCTAssertEqual(SettingsKeys.loadShortcut(), .defaultShortcut, "unset falls back")

        defaults.set(Data("not json at all".utf8), forKey: key)
        XCTAssertEqual(SettingsKeys.loadShortcut(), .defaultShortcut, "corrupt data falls back")

        // Decodable but invalid: a bare letter would capture ordinary typing.
        let bareKey = try JSONEncoder().encode(
            Shortcut(keyCode: 11, carbonModifiers: 0, display: "B"))
        defaults.set(bareKey, forKey: key)
        XCTAssertEqual(SettingsKeys.loadShortcut(), .defaultShortcut,
                       "modifier-less chord is rejected at the trust boundary")

        // Shift-only is also just typing.
        let shiftOnly = try JSONEncoder().encode(
            Shortcut(keyCode: 11, carbonModifiers: UInt32(shiftKey), display: "⇧B"))
        defaults.set(shiftOnly, forKey: key)
        XCTAssertEqual(SettingsKeys.loadShortcut(), .defaultShortcut)

        // A valid one survives the round trip.
        let valid = Shortcut(keyCode: 49, carbonModifiers: UInt32(controlKey), display: "⌃Space")
        SettingsKeys.save(valid)
        XCTAssertEqual(SettingsKeys.loadShortcut(), valid)
    }

    func testShortcutFromEventBuildsDisplayString() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .option],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: 49
        ))
        let shortcut = Shortcut.from(event: event)
        XCTAssertEqual(shortcut.keyCode, 49)
        XCTAssertEqual(shortcut.carbonModifiers, UInt32(optionKey | cmdKey))
        XCTAssertEqual(shortcut.display, "⌥⌘Space")
        XCTAssertEqual(shortcut, .defaultShortcut, "matches the shipped default")
    }
}
