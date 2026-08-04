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
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}
