import Foundation

struct PadID: RawRepresentable, Codable, Hashable {
    let rawValue: UUID
    init(rawValue: UUID) { self.rawValue = rawValue }
    init() { self.rawValue = UUID() }
}

struct StoredSelection: Codable, Equatable {
    var utf16Location: Int
    var utf16Length: Int

    static let zero = StoredSelection(utf16Location: 0, utf16Length: 0)

    // NSTextView selections are UTF-16 NSRanges; clamp against the current
    // text because content may have changed since the selection was stored.
    func clamped(toTextLength length: Int) -> NSRange {
        let location = min(max(0, utf16Location), length)
        let maxLength = length - location
        return NSRange(location: location, length: min(max(0, utf16Length), maxLength))
    }
}

enum PadColorIdentifier: String, CaseIterable, Codable {
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case purple
    case pink

    static let fallbackPalette: [PadColorIdentifier] = [
        .yellow,
        .orange,
        .red,
        .purple,
        .blue,
        .teal,
        .green,
        .pink,
    ]
}

enum PadCustomizationError: LocalizedError, Equatable {
    case workspaceUnavailable
    case unknownPad
    case invalidName
    case nameTooLong
    case invalidColor
    case metadataWriteFailed

    var errorDescription: String? {
        switch self {
        case .workspaceUnavailable:
            "The workspace is not available."
        case .unknownPad:
            "That scratchpad no longer exists."
        case .invalidName:
            "Pad names cannot contain line breaks, tabs, or control characters."
        case .nameTooLong:
            "Pad names can contain at most \(PadMetadata.maximumNameLength) characters."
        case .invalidColor:
            "That pad color is not supported."
        case .metadataWriteFailed:
            "The pad settings could not be saved."
        }
    }
}

struct PadMetadata: Codable, Equatable {
    let id: PadID
    var position: Int
    var name: String?
    var colorIdentifier: String?
    var selection: StoredSelection
    var scrollOffset: Double
    var contentRevision: UInt64
    var updatedAt: Date

    static let maximumNameLength = 24

    var defaultName: String {
        "Scratchpad \(position + 1)"
    }

    var displayName: String {
        Self.normalizedName(name) ?? defaultName
    }

    var accessibilityName: String {
        guard let name = Self.normalizedName(name) else { return defaultName }
        return "\(defaultName), \(name)"
    }

    var resolvedColorIdentifier: PadColorIdentifier {
        if let colorIdentifier,
           let color = PadColorIdentifier(rawValue: colorIdentifier.lowercased()) {
            return color
        }
        return PadColorIdentifier.fallbackPalette[
            position % PadColorIdentifier.fallbackPalette.count
        ]
    }

    static func normalizedName(_ candidate: String?) -> String? {
        guard let candidate else { return nil }
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func validatedName(_ candidate: String?) throws -> String? {
        let forbiddenScalars = CharacterSet.controlCharacters.union(.newlines)
        if let candidate,
           candidate.unicodeScalars.contains(where: forbiddenScalars.contains) {
            throw PadCustomizationError.invalidName
        }
        guard let normalized = normalizedName(candidate) else { return nil }
        guard normalized.count <= maximumNameLength else {
            throw PadCustomizationError.nameTooLong
        }
        return normalized
    }

    static func empty(position: Int, id: PadID = PadID(), now: Date = Date()) -> PadMetadata {
        PadMetadata(
            id: id,
            position: position,
            name: nil,
            colorIdentifier: nil,
            selection: .zero,
            scrollOffset: 0,
            contentRevision: 0,
            updatedAt: now
        )
    }
}

struct WorkspaceMetadata: Codable {
    var schemaVersion: Int
    var selectedPadID: PadID
    var pads: [PadMetadata]
    var lastCleanShutdown: Bool

    static let padCount = 8
    static let currentSchemaVersion = 1

    static func fresh(adoptingPadIDs adopted: [PadID] = [], now: Date = Date()) -> WorkspaceMetadata {
        let pads = (0..<padCount).map { position in
            PadMetadata.empty(
                position: position,
                id: position < adopted.count ? adopted[position] : PadID(),
                now: now
            )
        }
        return WorkspaceMetadata(
            schemaVersion: currentSchemaVersion,
            selectedPadID: pads[0].id,
            pads: pads,
            lastCleanShutdown: false
        )
    }

    // Deterministic invariant repair (plan §7.4): fixed pad count, unique IDs,
    // contiguous positions, valid selected pad. Extra pad files are retained.
    func repaired(now: Date = Date()) -> WorkspaceMetadata {
        var seen = Set<PadID>()
        var pads = self.pads.filter { seen.insert($0.id).inserted }
        pads.sort {
            ($0.position, $0.id.rawValue.uuidString) < ($1.position, $1.id.rawValue.uuidString)
        }
        if pads.count > Self.padCount {
            pads = Array(pads.prefix(Self.padCount))
        }
        while pads.count < Self.padCount {
            pads.append(.empty(position: pads.count, now: now))
        }
        for index in pads.indices {
            pads[index].position = index
        }
        var repaired = self
        repaired.schemaVersion = Self.currentSchemaVersion
        repaired.pads = pads
        if !pads.contains(where: { $0.id == selectedPadID }) {
            repaired.selectedPadID = pads[0].id
        }
        return repaired
    }
}

// One JSON line per acknowledged edit; full snapshots, not diffs (plan §9.2).
struct JournalEntry: Codable {
    let revision: UInt64
    let timestamp: Date
    let text: String
}
