import AppKit

@MainActor
protocol PadCustomizationManaging: AnyObject {
    var padMetadata: [PadMetadata] { get }

    @discardableResult
    func updatePadAppearance(
        _ id: PadID,
        name: String?,
        colorIdentifier: String?
    ) async throws -> PadMetadata

}

@MainActor
protocol SettingsWorkspaceManaging: PadCustomizationManaging {
    func createSettingsBackup() async -> Bool
    func restoreBackupFromSettings()
}

extension PadColorIdentifier {
    var color: NSColor {
        NSColor(name: NSColor.Name("BetterTotPadColor.\(rawValue)")) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value: UInt32 = switch (self, dark) {
            case (.red, false): 0xC12735
            case (.orange, false): 0xC2410C
            case (.yellow, false): 0x8A7000
            case (.green, false): 0x0F7F3D
            case (.teal, false): 0x007C83
            case (.blue, false): 0x2467C9
            case (.purple, false): 0x8B45B5
            case (.pink, false): 0xB62B67
            case (.red, true): 0xFF6961
            case (.orange, true): 0xFF9F0A
            case (.yellow, true): 0xFFD60A
            case (.green, true): 0x32D74B
            case (.teal, true): 0x40C8E0
            case (.blue, true): 0x0A84FF
            case (.purple, true): 0xBF5AF2
            case (.pink, true): 0xFF375F
            }
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}
