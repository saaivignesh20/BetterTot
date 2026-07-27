import AppKit
import Carbon.HIToolbox

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var display: String

    static let defaultShortcut = Shortcut(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(optionKey | cmdKey),
        display: "⌥⌘Space"
    )

    // F1–F20; self-contained keys that may stand alone as shortcuts.
    static let functionKeyCodes: Set<UInt32> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    // Plan §4.2: reject invalid shortcuts before saving. A shortcut must
    // carry ⌘, ⌥, or ⌃ so ordinary typing can never trigger it (shift alone
    // is just typing); function keys are exempt.
    static func isValid(keyCode: UInt32, carbonModifiers: UInt32) -> Bool {
        if functionKeyCodes.contains(keyCode) { return true }
        return carbonModifiers & UInt32(cmdKey | optionKey | controlKey) != 0
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    // Standard macOS symbol order: ⌃⌥⇧⌘.
    static func modifierSymbols(_ carbonModifiers: UInt32) -> String {
        var symbols = ""
        if carbonModifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return symbols
    }

    static func keyName(keyCode: UInt32, fallback: String?) -> String {
        let named: [UInt32: String] = [
            49: "Space", 36: "↩", 48: "⇥", 53: "⎋", 51: "⌫", 117: "⌦",
            123: "←", 124: "→", 126: "↑", 125: "↓",
            115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
            79: "F18", 80: "F19", 90: "F20",
        ]
        if let name = named[keyCode] { return name }
        if let fallback, !fallback.isEmpty { return fallback.uppercased() }
        return "Key \(keyCode)"
    }

    static func from(event: NSEvent) -> Shortcut {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        let code = UInt32(event.keyCode)
        let name = keyName(keyCode: code, fallback: event.charactersIgnoringModifiers)
        return Shortcut(keyCode: code, carbonModifiers: modifiers,
                        display: modifierSymbols(modifiers) + name)
    }
}

// Abstraction per plan §4.2 so the Carbon mechanism can be replaced later.
protocol GlobalShortcutService: AnyObject {
    var currentShortcut: Shortcut? { get }
    func register(_ shortcut: Shortcut) throws
    func unregister()
}

enum ShortcutError: LocalizedError {
    case registrationFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "The shortcut could not be registered (error \(status)). "
                + "It may already be in use by another app or by macOS."
        }
    }
}

final class CarbonGlobalShortcutService: GlobalShortcutService {
    private(set) var currentShortcut: Shortcut?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPress: () -> Void

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        // The handler outlives individual hot-key registrations.
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                Unmanaged<CarbonGlobalShortcutService>.fromOpaque(userData!)
                    .takeUnretainedValue().onPress()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }

    func register(_ shortcut: Shortcut) throws {
        unregister()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4254_4F54), id: 1) // 'BTOT'
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr, hotKeyRef != nil else {
            hotKeyRef = nil
            throw ShortcutError.registrationFailed(status)
        }
        currentShortcut = shortcut
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
        currentShortcut = nil
    }

    deinit {
        unregister()
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
    }
}
