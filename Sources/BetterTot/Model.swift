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

struct PadMetadata: Codable, Equatable {
    let id: PadID
    var position: Int
    var name: String?
    var colorIdentifier: String?
    var selection: StoredSelection
    var scrollOffset: Double
    var contentRevision: UInt64
    var updatedAt: Date

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

    static let padCount = 7
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

    // Deterministic invariant repair (plan §7.4): exactly seven pads, unique
    // IDs, positions 0…6, valid selected pad. Extra pad *files* on disk are
    // never deleted here — only metadata entries beyond seven are dropped.
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
