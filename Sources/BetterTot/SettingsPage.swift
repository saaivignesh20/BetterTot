import AppKit

enum SettingsPage: Int, CaseIterable {
    case general
    case pads
    case editor
    case storage
    case updates

    var title: String {
        switch self {
        case .general: "General"
        case .pads: "Pads"
        case .editor: "Editor"
        case .storage: "Storage"
        case .updates: "Updates"
        }
    }

    var identifier: String { title.lowercased() }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .pads: "circle.grid.2x2"
        case .editor: "pencil"
        case .storage: "internaldrive"
        case .updates: "arrow.clockwise"
        }
    }
}

enum BackupDisplayFormatting {
    static func date(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func size(_ bytes: Int64) -> String {
        sizeFormatter.string(fromByteCount: bytes)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        return formatter
    }()
}
