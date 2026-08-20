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
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .purple: .systemPurple
        case .pink: .systemPink
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}
