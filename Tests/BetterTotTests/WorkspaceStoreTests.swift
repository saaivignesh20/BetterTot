import XCTest
@testable import BetterTot

final class WorkspaceStoreTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettertot-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(root: root)
    }

    private func padsDir() -> URL { root.appendingPathComponent("Pads") }
    private func metadataURL() -> URL { root.appendingPathComponent("workspace.json") }
    private func journalURL(_ id: PadID) -> URL {
        root.appendingPathComponent("Journal/\(id.rawValue.uuidString).log")
    }

    // MARK: - Workspace invariants

    func testFreshWorkspaceCreatesSevenPads() async throws {
        XCTAssertEqual(WorkspaceMetadata.padCount, 7)
        let store = makeStore()
        let snapshot = try await store.load()
        XCTAssertEqual(snapshot.metadata.pads.count, WorkspaceMetadata.padCount)
        XCTAssertEqual(Set(snapshot.metadata.pads.map(\.id)).count, WorkspaceMetadata.padCount)
        XCTAssertEqual(
            snapshot.metadata.pads.map(\.position).sorted(),
            Array(0..<WorkspaceMetadata.padCount)
        )
        XCTAssertTrue(snapshot.metadata.pads.contains { $0.id == snapshot.metadata.selectedPadID })
        XCTAssertEqual(
            snapshot.texts.values.filter { $0.isEmpty }.count,
            WorkspaceMetadata.padCount
        )
        XCTAssertFalse(snapshot.metadata.lastCleanShutdown)
    }

    func testLegacyEighthPadRemainsExportableWhileHiddenFromTheActiveSet() async throws {
        let pads = (0..<8).map { PadMetadata.empty(position: $0) }
        let removedPad = pads[7]
        let metadata = WorkspaceMetadata(
            schemaVersion: WorkspaceMetadata.currentSchemaVersion,
            selectedPadID: removedPad.id,
            pads: pads,
            lastCleanShutdown: false
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: metadataURL(), options: .atomic)
        try FileManager.default.createDirectory(
            at: padsDir(),
            withIntermediateDirectories: true
        )
        let removedPadURL = padsDir().appendingPathComponent(
            "\(removedPad.id.rawValue.uuidString).txt"
        )
        try "legacy eighth pad".write(
            to: removedPadURL,
            atomically: true,
            encoding: .utf8
        )

        let store = makeStore()
        let snapshot = try await store.load()

        XCTAssertEqual(snapshot.metadata.pads.count, 8)
        XCTAssertTrue(snapshot.metadata.pads.contains { $0.id == removedPad.id })
        XCTAssertEqual(snapshot.metadata.selectedPadID, snapshot.metadata.pads[0].id)
        XCTAssertEqual(
            try String(contentsOf: removedPadURL, encoding: .utf8),
            "legacy eighth pad"
        )

        let export = root.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        try await store.exportAllPads(to: export)
        XCTAssertEqual(
            try String(contentsOf: export.appendingPathComponent("Pad 8.txt"), encoding: .utf8),
            "legacy eighth pad"
        )

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.metadata.pads.count, 8)
        XCTAssertEqual(
            try String(contentsOf: removedPadURL, encoding: .utf8),
            "legacy eighth pad"
        )
    }

    func testOrphanedEighthPadIsReattachedAfterInterruptedMigration() async throws {
        let metadata = WorkspaceMetadata.fresh()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(metadata).write(to: metadataURL(), options: .atomic)
        try FileManager.default.createDirectory(
            at: padsDir(),
            withIntermediateDirectories: true
        )
        let orphanID = PadID()
        try "reattached legacy pad".write(
            to: padsDir().appendingPathComponent("\(orphanID.rawValue.uuidString).txt"),
            atomically: true,
            encoding: .utf8
        )

        let snapshot = try await makeStore().load()

        XCTAssertEqual(snapshot.metadata.pads.count, 8)
        XCTAssertEqual(snapshot.metadata.pads[7].id, orphanID)
        XCTAssertEqual(snapshot.texts[orphanID], "reattached legacy pad")
    }

    func testMetadataRebuildRetainsAllEightLegacyPadFiles() async throws {
        try FileManager.default.createDirectory(
            at: padsDir(),
            withIntermediateDirectories: true
        )
        let contents = (0..<8).map { "legacy pad \($0 + 1)" }
        for content in contents {
            try content.write(
                to: padsDir().appendingPathComponent("\(UUID().uuidString).txt"),
                atomically: true,
                encoding: .utf8
            )
        }

        let snapshot = try await makeStore().load()

        XCTAssertEqual(snapshot.metadata.pads.count, 8)
        XCTAssertEqual(Set(snapshot.texts.values), Set(contents))
    }

    func testRepairFixesDuplicatePositionsAndIDs() {
        let a = PadMetadata.empty(position: 3)
        let b = PadMetadata.empty(position: 3)
        var meta = WorkspaceMetadata.fresh()
        meta.pads = [a, b, a] // duplicate ID and duplicate positions
        meta.selectedPadID = PadID() // dangling selection
        let repaired = meta.repaired()
        XCTAssertEqual(repaired.pads.count, WorkspaceMetadata.padCount)
        XCTAssertEqual(Set(repaired.pads.map(\.id)).count, WorkspaceMetadata.padCount)
        XCTAssertEqual(repaired.pads.map(\.position), Array(0..<WorkspaceMetadata.padCount))
        XCTAssertTrue(repaired.pads.contains { $0.id == repaired.selectedPadID })
        // deterministic: same input repairs the same way twice
        XCTAssertEqual(meta.repaired().pads.map(\.id).prefix(2), repaired.pads.map(\.id).prefix(2))
    }

    // MARK: - Commit and reload

    func testCommitAndReloadRoundTrip() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        let text = "hello\nworld 🙂 日本語\ntrailing newline\n"
        await store.commit(id, text: text, revision: 1)

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.texts[id], text)
        XCTAssertEqual(reloaded.metadata.pads.first { $0.id == id }?.contentRevision, 1)
    }

    func testStaleCommitRevisionIsIgnored() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        await store.commit(id, text: "newer", revision: 5)
        await store.commit(id, text: "stale", revision: 3)
        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.texts[id], "newer")
    }

    func testPadAppearanceUpdateValidatesNormalizesAndPersists() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let pad = snapshot.metadata.pads[0]
        let selection = StoredSelection(utf16Location: 2, utf16Length: 3)
        await store.updatePadState(pad.id, selection: selection, scrollOffset: 42)
        let committed = await store.commit(pad.id, text: "keep this text", revision: 1)
        XCTAssertTrue(committed)

        let updated = try await store.updatePadAppearance(
            pad.id,
            name: "  Research  ",
            colorIdentifier: PadColorIdentifier.blue.rawValue
        )

        XCTAssertEqual(updated.name, "Research")
        XCTAssertEqual(updated.colorIdentifier, PadColorIdentifier.blue.rawValue)
        XCTAssertEqual(updated.contentRevision, 1)
        XCTAssertEqual(updated.selection, selection)
        XCTAssertEqual(updated.scrollOffset, 42)

        let reloaded = try await makeStore().load()
        let persisted = try XCTUnwrap(reloaded.metadata.pads.first { $0.id == pad.id })
        XCTAssertEqual(persisted.name, "Research")
        XCTAssertEqual(persisted.colorIdentifier, PadColorIdentifier.blue.rawValue)
        XCTAssertEqual(persisted.selection, selection)
        XCTAssertEqual(persisted.scrollOffset, 42)
        XCTAssertEqual(reloaded.texts[pad.id], "keep this text")

        let cleared = try await store.updatePadAppearance(
            pad.id,
            name: "   ",
            colorIdentifier: nil
        )
        XCTAssertNil(cleared.name)
        XCTAssertNil(cleared.colorIdentifier)
    }

    func testPadAppearanceUpdateRejectsInvalidInputWithoutChangingMetadata() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let pad = snapshot.metadata.pads[0]

        do {
            _ = try await store.updatePadAppearance(
                pad.id,
                name: String(repeating: "x", count: PadMetadata.maximumNameLength + 1),
                colorIdentifier: PadColorIdentifier.red.rawValue
            )
            XCTFail("oversized names must be rejected")
        } catch {
            XCTAssertEqual(error as? PadCustomizationError, .nameTooLong)
        }

        do {
            _ = try await store.updatePadAppearance(
                pad.id,
                name: "Research\nPrivate",
                colorIdentifier: PadColorIdentifier.red.rawValue
            )
            XCTFail("control characters must be rejected")
        } catch {
            XCTAssertEqual(error as? PadCustomizationError, .invalidName)
        }

        do {
            _ = try await store.updatePadAppearance(
                pad.id,
                name: "Research\u{2028}Private",
                colorIdentifier: PadColorIdentifier.red.rawValue
            )
            XCTFail("Unicode line separators must be rejected")
        } catch {
            XCTAssertEqual(error as? PadCustomizationError, .invalidName)
        }

        do {
            _ = try await store.updatePadAppearance(
                pad.id,
                name: "Research",
                colorIdentifier: "chartreuse"
            )
            XCTFail("unknown colors must be rejected")
        } catch {
            XCTAssertEqual(error as? PadCustomizationError, .invalidColor)
        }

        do {
            _ = try await store.updatePadAppearance(
                PadID(),
                name: "Research",
                colorIdentifier: PadColorIdentifier.red.rawValue
            )
            XCTFail("unknown pads must be rejected")
        } catch {
            XCTAssertEqual(error as? PadCustomizationError, .unknownPad)
        }

        let current = await store.currentMetadata()?.pads.first { $0.id == pad.id }
        XCTAssertEqual(current, pad)
    }

    // MARK: - Journal recovery

    func testJournaledEditWithoutCommitIsRecovered() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[2].id
        await store.commit(id, text: "committed", revision: 1)
        await store.journal(id, text: "committed plus crash-lost typing", revision: 2)
        // no commit for revision 2 — simulates SIGKILL before the debounce fired

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.texts[id], "committed plus crash-lost typing")
        XCTAssertEqual(reloaded.metadata.pads.first { $0.id == id }?.contentRevision, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL(id).path),
                       "journal is cleared after recovery")
    }

    func testCommitClearsJournal() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        await store.journal(id, text: "typing", revision: 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalURL(id).path))
        await store.commit(id, text: "typing", revision: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL(id).path))
    }

    func testTruncatedJournalLineIsIgnoredValidLinesStillRecover() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        await store.journal(id, text: "good entry", revision: 1)
        // simulate a crash mid-append: garbage partial line at the end
        let handle = try FileHandle(forWritingTo: journalURL(id))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"revision\":2,\"text\":\"trunc".utf8))
        try handle.close()

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.texts[id], "good entry")
    }

    func testStaleJournalEntryDoesNotOverwriteNewerCommit() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        await store.commit(id, text: "newer committed", revision: 5)
        // hand-craft a stale journal entry (revision below the committed one)
        let entry = "{\"revision\":2,\"text\":\"old journaled\",\"timestamp\":\"2026-01-01T00:00:00Z\"}\n"
        try Data(entry.utf8).write(to: journalURL(id))

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.texts[id], "newer committed")
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL(id).path))
    }

    func testRecoveryPreservesPreviousFileVersion() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        await store.commit(id, text: "old version", revision: 1)
        await store.journal(id, text: "new version", revision: 2)

        _ = try await makeStore().load()
        let recovered = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Journal/recovered"),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(recovered.count, 1)
        XCTAssertEqual(try String(contentsOf: recovered[0], encoding: .utf8), "old version")
    }

    // MARK: - Corruption and damage containment

    func testCorruptedMetadataPreservesPadText() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        await store.commit(id, text: "precious text", revision: 1)
        try Data("{not json!!".utf8).write(to: metadataURL())

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.metadata.pads.count, WorkspaceMetadata.padCount)
        XCTAssertTrue(reloaded.texts.values.contains("precious text"),
                      "pad text survives metadata corruption")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("workspace.json.corrupt").path),
            "corrupt metadata is preserved for manual recovery")
    }

    func testMissingPadFileIsHandledSafely() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let keepID = snapshot.metadata.pads[0].id
        let loseID = snapshot.metadata.pads[1].id
        await store.commit(keepID, text: "survivor", revision: 1)
        await store.commit(loseID, text: "will vanish", revision: 1)
        try FileManager.default.removeItem(
            at: padsDir().appendingPathComponent("\(loseID.rawValue.uuidString).txt"))

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.texts[loseID], "", "missing pad reloads empty, no crash")
        XCTAssertEqual(reloaded.texts[keepID], "survivor", "other pads untouched")
    }

    func testOrphanPadFileIsAdoptedWithTextIntact() async throws {
        _ = try await makeStore().load()
        let strangerID = UUID().uuidString
        let stranger = padsDir().appendingPathComponent("\(strangerID).txt")
        try Data("orphaned but precious".utf8).write(to: stranger)
        try Data("{not json".utf8).write(to: metadataURL()) // force full rebuild

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.metadata.pads.count, WorkspaceMetadata.padCount)
        XCTAssertTrue(reloaded.metadata.pads.contains { $0.id.rawValue.uuidString == strangerID })
        XCTAssertTrue(reloaded.texts.values.contains("orphaned but precious"),
                      "adopted orphan keeps its text")
        XCTAssertEqual(try String(contentsOf: stranger, encoding: .utf8), "orphaned but precious",
                       "orphan file content untouched on disk")
    }

    func testPadFilesBeyondLimitSurviveMetadataRebuildOnDisk() async throws {
        _ = try await makeStore().load()
        // Ten pad files, including the single legacy-compatible pad, can be adopted.
        var files: [URL] = []
        for index in 0..<10 {
            let url = padsDir().appendingPathComponent("\(UUID().uuidString).txt")
            try Data("content \(index)".utf8).write(to: url)
            files.append(url)
        }
        try Data("{not json".utf8).write(to: metadataURL())

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.metadata.pads.count, WorkspaceMetadata.compatibleBackupPadCount)
        for url in files {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                          "unadopted pad files must never be deleted")
        }
    }

    func testCorruptedMetadataDoesNotCrossContaminatePadTexts() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        for (offset, text) in ["alpha", "beta", "gamma"].enumerated() {
            await store.commit(snapshot.metadata.pads[offset].id, text: text, revision: 1)
        }
        try Data("{not json".utf8).write(to: metadataURL())

        let reloaded = try await makeStore().load()
        // every adopted pad's in-memory text matches its own file on disk
        for pad in reloaded.metadata.pads {
            let onDisk = (try? String(
                contentsOf: padsDir().appendingPathComponent("\(pad.id.rawValue.uuidString).txt"),
                encoding: .utf8)) ?? ""
            XCTAssertEqual(reloaded.texts[pad.id], onDisk)
        }
        XCTAssertEqual(
            Set(reloaded.texts.values.filter { !$0.isEmpty }), ["alpha", "beta", "gamma"])
    }

    // MARK: - Torn-write and failure-path recovery

    func testTornJournalTailWithInvalidUTF8StillRecoversEarlierEntries() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        await store.journal(id, text: "note with emoji 🙂", revision: 1)
        // SIGKILL mid-append: torn line ending inside a 4-byte emoji sequence
        let handle = try FileHandle(forWritingTo: journalURL(id))
        try handle.seekToEnd()
        var torn = Data("{\"revision\":2,\"text\":\"x".utf8)
        torn.append(contentsOf: [0xF0, 0x9F]) // first half of an emoji
        try handle.write(contentsOf: torn)
        try handle.close()

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.texts[id], "note with emoji 🙂",
                       "intact entries survive a tail torn mid-multi-byte UTF-8")
    }

    func testNewestOfMultipleJournalEntriesWins() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        await store.journal(id, text: "a", revision: 1)
        await store.journal(id, text: "ab", revision: 2)
        await store.journal(id, text: "abc", revision: 3)

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.texts[id], "abc")
        XCTAssertEqual(reloaded.revisions[id], 3)
    }

    func testJournalEntryEqualToCommittedRevisionIsIgnoredAndCleared() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        await store.commit(id, text: "committed", revision: 3)
        let entry = "{\"revision\":3,\"text\":\"same revision\",\"timestamp\":\"2026-01-01T00:00:00Z\"}\n"
        try Data(entry.utf8).write(to: journalURL(id))

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.texts[id], "committed", "strict > comparison, no needless rewrite")
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL(id).path))
    }

    func testRecoveryWriteFailureKeepsJournalAndRetriesNextLaunch() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        await store.commit(id, text: "old", revision: 1)
        await store.journal(id, text: "acknowledged edit", revision: 2)
        // make the pad write fail while Journal/ stays writable
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: padsDir().path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: padsDir().path)
        }

        let failed = try await makeStore().load()
        XCTAssertEqual(failed.texts[id], "acknowledged edit", "journaled text still shown in memory")
        XCTAssertEqual(failed.revisions[id], 2, "UI revision seeds from the journal for auto-retry")
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalURL(id).path),
                      "journal survives a failed recovery write")
        let persisted = try JSONDecoder.iso.decode(
            WorkspaceMetadata.self, from: Data(contentsOf: metadataURL()))
        XCTAssertEqual(persisted.pads.first { $0.id == id }?.contentRevision, 1,
                       "metadata never claims a revision the file does not contain")

        // permissions restored -> next launch completes the recovery
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: padsDir().path)
        let recovered = try await makeStore().load()
        XCTAssertEqual(recovered.texts[id], "acknowledged edit")
        XCTAssertEqual(recovered.metadata.pads.first { $0.id == id }?.contentRevision, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL(id).path))
    }

    func testUnreadablePadFileIsPreservedBeforeAnyOverwrite() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        await store.commit(id, text: "was readable", revision: 1)
        // corrupt the file: invalid UTF-8 bytes
        let padFile = padsDir().appendingPathComponent("\(id.rawValue.uuidString).txt")
        let corruptBytes = Data([0x68, 0x69, 0xFF, 0xFE, 0x6F])
        try corruptBytes.write(to: padFile)

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.texts[id], "", "unreadable pad opens empty rather than crashing")
        let preserved = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Journal/recovered"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "corrupt" }
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try Data(contentsOf: preserved[0]), corruptBytes,
                       "raw bytes preserved before any commit can overwrite the file")
    }

    // MARK: - Empty-text durability (pad clearing is acknowledged state)

    func testEmptyCommitOverwritesNonEmptyPadAndPersists() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        await store.commit(id, text: "content", revision: 1)
        await store.commit(id, text: "", revision: 2)

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.texts[id], "", "a cleared pad stays cleared after relaunch")
        XCTAssertEqual(reloaded.metadata.pads.first { $0.id == id }?.contentRevision, 2)
    }

    func testJournaledClearIsRecoveredAndOldTextPreserved() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        await store.commit(id, text: "about to be cleared", revision: 1)
        await store.journal(id, text: "", revision: 2) // clear, then SIGKILL before commit

        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded.texts[id], "", "journaled clear is acknowledged state")
        let preserved = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Journal/recovered"), includingPropertiesForKeys: nil)
        XCTAssertEqual(preserved.count, 1)
        XCTAssertEqual(try String(contentsOf: preserved[0], encoding: .utf8), "about to be cleared")
    }

    // MARK: - Legacy migration

    func testPhaseZeroSinglePadFileIsMigrated() async throws {
        try Data("spike note".utf8).write(to: root.appendingPathComponent("pad.txt"))
        let snapshot = try await makeStore().load()
        XCTAssertTrue(snapshot.texts.values.contains("spike note"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("pad.txt").path))
    }

    // MARK: - Clean-shutdown marker

    func testCleanShutdownMarker() async throws {
        let store = makeStore()
        _ = try await store.load()
        await store.markCleanShutdown()
        let data = try Data(contentsOf: metadataURL())
        let meta = try JSONDecoder.iso.decode(WorkspaceMetadata.self, from: data)
        XCTAssertTrue(meta.lastCleanShutdown)

        // next launch resets it to false while the session is live
        _ = try await makeStore().load()
        let relaunched = try JSONDecoder.iso.decode(
            WorkspaceMetadata.self, from: Data(contentsOf: metadataURL()))
        XCTAssertFalse(relaunched.lastCleanShutdown)
    }

    // MARK: - Selection clamping

    func testSelectionClampingAgainstShorterAndUnicodeText() {
        XCTAssertEqual(StoredSelection(utf16Location: 10, utf16Length: 10)
            .clamped(toTextLength: 5), NSRange(location: 5, length: 0))
        XCTAssertEqual(StoredSelection(utf16Location: 2, utf16Length: 100)
            .clamped(toTextLength: 5), NSRange(location: 2, length: 3))
        XCTAssertEqual(StoredSelection(utf16Location: -3, utf16Length: -1)
            .clamped(toTextLength: 5), NSRange(location: 0, length: 0))
        let emoji = "🙂🙂" as NSString // 4 UTF-16 units
        XCTAssertEqual(StoredSelection(utf16Location: 0, utf16Length: 99)
            .clamped(toTextLength: emoji.length), NSRange(location: 0, length: 4))
    }
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
