import Foundation

struct WorkspaceSnapshot {
    let metadata: WorkspaceMetadata
    let texts: [PadID: String]
    // Seed for the UI's revision counters. Usually contentRevision, but after
    // a failed recovery write it is the journaled revision, so the next
    // commit (revision+1 > contentRevision) retries the write automatically.
    let revisions: [PadID: UInt64]
}

// Serializes all disk I/O (plan §8.4). The UI layer owns in-memory state and
// treats this actor as the single writer of pad files, journals, and metadata.
actor WorkspaceStore {
    let root: URL
    let backupRepositoryLocation: BackupRepositoryLocation
    let legacyBackupDirectories: [URL]
    let backupRepositoryLocationResolver: (any ICloudBackupLocationResolving)?
    private var metadata: WorkspaceMetadata?
    private var journaledRevisions: [PadID: UInt64] = [:]
    private var padsDir: URL { root.appendingPathComponent("Pads", isDirectory: true) }
    private var journalDir: URL { root.appendingPathComponent("Journal", isDirectory: true) }
    private var recoveredDir: URL { journalDir.appendingPathComponent("recovered", isDirectory: true) }
    private var metadataURL: URL { root.appendingPathComponent("workspace.json") }

    init(
        root: URL,
        backupRepositoryLocation: BackupRepositoryLocation? = nil,
        backupRepositoryLocationResolver: (any ICloudBackupLocationResolving)? = nil,
        legacyBackupDirectories: [URL] = []
    ) {
        self.root = root
        self.backupRepositoryLocation = backupRepositoryLocation
            ?? backupRepositoryLocationResolver?.resolve()
            ?? .available(root.appendingPathComponent("Backups", isDirectory: true))
        self.backupRepositoryLocationResolver = backupRepositoryLocationResolver
        self.legacyBackupDirectories = legacyBackupDirectories.map(\.standardizedFileURL)
    }

    static func defaultRoot() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BetterTot", isDirectory: true)
    }

    // MARK: - Load, repair, recover

    func load() throws -> WorkspaceSnapshot {
        for dir in [root, padsDir, journalDir, recoveredDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        migrateLegacySinglePadIfNeeded()

        var meta = loadOrRebuildMetadata().repaired()
        var texts: [PadID: String] = [:]
        for pad in meta.pads {
            let url = padURL(pad.id)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                texts[pad.id] = text
            } else {
                // Distinguish missing from unreadable: an existing file that
                // fails strict UTF-8 decode gets its raw bytes preserved
                // before any later commit can atomically overwrite it.
                if FileManager.default.fileExists(atPath: url.path) {
                    let stamp = UInt64(Date().timeIntervalSince1970)
                    let target = recoveredDir.appendingPathComponent(
                        "\(pad.id.rawValue.uuidString)-\(stamp).corrupt")
                    try? FileManager.default.copyItem(at: url, to: target)
                    NSLog("BetterTot: pad %d file unreadable, raw bytes preserved", pad.position)
                }
                texts[pad.id] = ""
            }
        }

        // Journal recovery: any surviving entry newer than the committed
        // revision is an acknowledged edit that never reached the pad file.
        var revisions: [PadID: UInt64] = [:]
        for index in meta.pads.indices {
            let pad = meta.pads[index]
            var effectiveRevision = pad.contentRevision
            if let entry = newestJournalEntry(for: pad.id), entry.revision > pad.contentRevision {
                preserveCurrentFile(for: pad.id, ifDiffersFrom: entry.text)
                texts[pad.id] = entry.text
                effectiveRevision = entry.revision
                if writePadFile(pad.id, text: entry.text) {
                    meta.pads[index].contentRevision = entry.revision
                    meta.pads[index].updatedAt = entry.timestamp
                    clearJournal(for: pad.id)
                    NSLog("BetterTot: recovered journaled edit for pad %d (revision %llu)",
                          pad.position, entry.revision)
                } else {
                    // Recovery write failed (e.g. disk full). Keep the journal
                    // so the next successful commit or launch retries; never
                    // let metadata claim a revision the file does not contain.
                    journaledRevisions[pad.id] = entry.revision
                    NSLog("BetterTot: recovery write failed for pad %d; journal retained",
                          pad.position)
                }
            } else {
                clearJournal(for: pad.id)
            }
            revisions[pad.id] = effectiveRevision
        }

        // Session is now live; the marker is a recovery hint only (plan §9.3).
        meta.lastCleanShutdown = false
        metadata = meta
        saveMetadata()
        migrateLegacyBackupsIfNeeded()
        return WorkspaceSnapshot(metadata: meta, texts: texts, revisions: revisions)
    }

    private func loadOrRebuildMetadata() -> WorkspaceMetadata {
        if let data = try? Data(contentsOf: metadataURL) {
            if let meta = try? Self.decoder.decode(WorkspaceMetadata.self, from: data),
               meta.schemaVersion == WorkspaceMetadata.currentSchemaVersion {
                return meta
            }
            // Preserve the unreadable file; never let bad metadata cost pad text.
            let corrupt = root.appendingPathComponent("workspace.json.corrupt")
            try? FileManager.default.removeItem(at: corrupt)
            try? FileManager.default.copyItem(at: metadataURL, to: corrupt)
            NSLog("BetterTot: workspace.json unreadable, rebuilding from pad files")
        }
        let adopted = ((try? FileManager.default.contentsOfDirectory(
            at: padsDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "txt" }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent) }
            .map(PadID.init(rawValue:))
            .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        return .fresh(adoptingPadIDs: adopted)
    }

    // Phase 0 spike stored a single root-level pad.txt; adopt it as a pad.
    private func migrateLegacySinglePadIfNeeded() {
        let legacy = root.appendingPathComponent("pad.txt")
        guard !FileManager.default.fileExists(atPath: metadataURL.path),
              FileManager.default.fileExists(atPath: legacy.path) else { return }
        try? FileManager.default.moveItem(
            at: legacy,
            to: padsDir.appendingPathComponent("\(UUID().uuidString).txt")
        )
    }

    // MARK: - Journal (append-only, one file per pad, cleared on commit)

    private func committedRevision(of id: PadID) -> UInt64 {
        metadata?.pads.first { $0.id == id }?.contentRevision ?? 0
    }

    @discardableResult
    func journal(_ id: PadID, text: String, revision: UInt64) -> Bool {
        guard revision > (journaledRevisions[id] ?? 0),
              revision > committedRevision(of: id) else { return true }
        guard var line = try? Self.compactEncoder.encode(JournalEntry(
            revision: revision, timestamp: Date(), text: text)) else { return false }
        line.append(0x0A)
        let url = journalURL(id)
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            journaledRevisions[id] = revision
            return true
        } catch {
            let diagnostic = error as NSError
            NSLog("BetterTot: journal append failed (%@:%ld)",
                  diagnostic.domain, diagnostic.code)
            return false
        }
    }

    private func newestJournalEntry(for id: PadID) -> JournalEntry? {
        guard let data = try? Data(contentsOf: journalURL(id)) else { return nil }
        // Split on raw newline BYTES, then decode each line independently: a
        // tail torn mid-multi-byte-UTF-8 by SIGKILL must not poison the whole
        // file the way a strict whole-file String decode would.
        return data.split(separator: 0x0A)
            .compactMap { try? Self.decoder.decode(JournalEntry.self, from: Data($0)) }
            .max { $0.revision < $1.revision }
    }

    private func clearJournal(for id: PadID) {
        try? FileManager.default.removeItem(at: journalURL(id))
        journaledRevisions[id] = nil
    }

    private func preserveCurrentFile(for id: PadID, ifDiffersFrom incoming: String) {
        // Byte-level compare so undecodable (corrupt) files are preserved too.
        guard let current = try? Data(contentsOf: padURL(id)),
              !current.isEmpty, current != Data(incoming.utf8) else { return }
        let stamp = UInt64(Date().timeIntervalSince1970)
        let target = recoveredDir.appendingPathComponent("\(id.rawValue.uuidString)-\(stamp).txt")
        try? FileManager.default.copyItem(at: padURL(id), to: target)
    }

    // MARK: - Commit (atomic pad write, then metadata)

    @discardableResult
    func commit(_ id: PadID, text: String, revision: UInt64) -> Bool {
        guard metadata != nil,
              let index = metadata!.pads.firstIndex(where: { $0.id == id }) else { return false }
        guard revision > metadata!.pads[index].contentRevision else { return true }
        guard writePadFile(id, text: text) else { return false } // journal keeps the edit recoverable
        metadata!.pads[index].contentRevision = revision
        metadata!.pads[index].updatedAt = Date()
        if revision >= (journaledRevisions[id] ?? 0) {
            clearJournal(for: id)
        }
        saveMetadata()
        autoBackupIfDue()
        return true
    }

    func updatePadState(_ id: PadID, selection: StoredSelection, scrollOffset: Double) {
        guard metadata != nil,
              let index = metadata!.pads.firstIndex(where: { $0.id == id }) else { return }
        metadata!.pads[index].selection = selection
        metadata!.pads[index].scrollOffset = scrollOffset
        saveMetadata()
    }

    func select(_ id: PadID) {
        guard metadata != nil, metadata!.pads.contains(where: { $0.id == id }) else { return }
        metadata!.selectedPadID = id
        saveMetadata()
    }

    func updatePadAppearance(
        _ id: PadID,
        name: String?,
        colorIdentifier: String?
    ) throws -> PadMetadata {
        guard let current = metadata else {
            throw PadCustomizationError.workspaceUnavailable
        }
        guard let index = current.pads.firstIndex(where: { $0.id == id }) else {
            throw PadCustomizationError.unknownPad
        }
        let validatedName = try PadMetadata.validatedName(name)
        let validatedColor: String?
        if let colorIdentifier {
            guard let color = PadColorIdentifier(rawValue: colorIdentifier.lowercased()) else {
                throw PadCustomizationError.invalidColor
            }
            validatedColor = color.rawValue
        } else {
            validatedColor = nil
        }

        var updatedPad = current.pads[index]
        updatedPad.name = validatedName
        updatedPad.colorIdentifier = validatedColor
        updatedPad.updatedAt = Date()

        var candidate = current
        candidate.pads[index] = updatedPad
        do {
            try writeMetadata(candidate)
        } catch {
            let diagnostic = error as NSError
            NSLog("BetterTot: metadata save failed (%@:%ld)",
                  diagnostic.domain, diagnostic.code)
            throw PadCustomizationError.metadataWriteFailed
        }
        metadata = candidate
        return updatedPad
    }

    func markCleanShutdown() {
        guard metadata != nil else { return }
        metadata!.lastCleanShutdown = true
        saveMetadata()
    }

    func currentMetadata() -> WorkspaceMetadata? {
        metadata
    }

    // MARK: - File helpers

    func padURL(_ id: PadID) -> URL {
        padsDir.appendingPathComponent("\(id.rawValue.uuidString).txt")
    }

    private func journalURL(_ id: PadID) -> URL {
        journalDir.appendingPathComponent("\(id.rawValue.uuidString).log")
    }

    @discardableResult
    private func writePadFile(_ id: PadID, text: String) -> Bool {
        do {
            try text.write(to: padURL(id), atomically: true, encoding: .utf8)
            return true
        } catch {
            // never log note contents, only the failure
            let diagnostic = error as NSError
            NSLog("BetterTot: pad save failed (%@:%ld)",
                  diagnostic.domain, diagnostic.code)
            return false
        }
    }

    private func saveMetadata() {
        guard let metadata else { return }
        do {
            try writeMetadata(metadata)
        } catch {
            let diagnostic = error as NSError
            NSLog("BetterTot: metadata save failed (%@:%ld)",
                  diagnostic.domain, diagnostic.code)
        }
    }

    private func writeMetadata(_ metadata: WorkspaceMetadata) throws {
        let data = try Self.encoder.encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let compactEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
