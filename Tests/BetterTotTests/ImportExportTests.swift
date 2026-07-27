import AppKit
import XCTest
@testable import BetterTot

@MainActor
final class ImportExportTests: XCTestCase {
    private var root: URL!
    private var statusItem: NSStatusItem!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettertot-import-export-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    }

    override func tearDownWithError() throws {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        try? FileManager.default.removeItem(at: root)
    }

    func testReadTextFileDetectsUTF8AndUTF16AndRejectsInvalidBytes() throws {
        let utf8 = root.appendingPathComponent("utf8.txt")
        let utf16 = root.appendingPathComponent("utf16.txt")
        let invalid = root.appendingPathComponent("invalid.txt")
        try "plain café".write(to: utf8, atomically: true, encoding: .utf8)
        try "wide text".write(to: utf16, atomically: true, encoding: .utf16)
        try Data([0xFF, 0xFE, 0xFF]).write(to: invalid)

        XCTAssertEqual(PanelController.readTextFile(utf8), "plain café")
        XCTAssertEqual(PanelController.readTextFile(utf16), "wide text")
        XCTAssertNil(PanelController.readTextFile(invalid))
    }

    func testReadTextFileRejectsSymlinksDirectoriesAndOversizedInputs() throws {
        let target = root.appendingPathComponent("target.txt")
        let symlink = root.appendingPathComponent("linked.txt")
        let oversized = root.appendingPathComponent("oversized.txt")
        try "private target".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        try Data(repeating: 0x41, count: PanelController.maximumImportedTextBytes + 1)
            .write(to: oversized)

        XCTAssertNil(PanelController.readTextFile(symlink))
        XCTAssertNil(PanelController.readTextFile(root))
        XCTAssertNil(PanelController.readTextFile(oversized))
    }

    func testImportCanReplaceAndAppendWithASeparatingNewline() async throws {
        let (controller, _, snapshot) = try await makeController()
        let selectedID = snapshot.metadata.selectedPadID

        controller.applyToCurrentPad("original", replacing: true)
        controller.applyToCurrentPad("appended", replacing: false)
        XCTAssertEqual(controller.textView.string, "original\nappended")

        controller.applyToCurrentPad("replacement", replacing: true)
        XCTAssertEqual(controller.textView.string, "replacement")
        await controller.flushAll()

        let reloaded = try await WorkspaceStore(root: root).load()
        XCTAssertEqual(reloaded.texts[selectedID], "replacement")
    }

    func testAppendDoesNotAddAnExtraNewlineWhenPadAlreadyEndsWithOne() async throws {
        let (controller, _, _) = try await makeController()

        controller.applyToCurrentPad("first\n", replacing: true)
        controller.applyToCurrentPad("second", replacing: false)

        XCTAssertEqual(controller.textView.string, "first\nsecond")
        await controller.flushAll()
    }

    func testRestoreUpdatesReadablePadsAndKeepsMissingOrUnreadablePads() async throws {
        let (controller, _, snapshot) = try await makeController()
        let pads = snapshot.metadata.pads.sorted { $0.position < $1.position }
        controller.applyToCurrentPad("keep selected", replacing: true)
        controller.selectPad(at: 1)
        controller.applyToCurrentPad("keep missing", replacing: true)
        controller.selectPad(at: 2)
        controller.applyToCurrentPad("keep unreadable", replacing: true)
        controller.commitCurrentPadNow()

        let backup = root.appendingPathComponent("restore", isDirectory: true)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
        try "restored selected".write(
            to: backup.appendingPathComponent("Pad 1.txt"), atomically: true, encoding: .utf8)
        try Data([0xE9, 0xFF, 0xFE]).write(to: backup.appendingPathComponent("Pad 3.txt"))
        let files = (1...WorkspaceMetadata.padCount).map {
            backup.appendingPathComponent("Pad \($0).txt")
        }

        let unreadable = await controller.restore(from: files)
        XCTAssertEqual(unreadable, [2])
        await controller.flushAll()

        let reloaded = try await WorkspaceStore(root: root).load()
        XCTAssertEqual(reloaded.texts[pads[0].id], "restored selected")
        XCTAssertEqual(reloaded.texts[pads[1].id], "keep missing")
        XCTAssertEqual(reloaded.texts[pads[2].id], "keep unreadable")
    }

    func testImportWorkflowHandlesEmptyAppendCancelAndBackedUpReplace() async throws {
        let (controller, store, _) = try await makeController()

        let initial = await controller.importText("first", choice: .replace)
        let appended = await controller.importText("second", choice: .append)
        XCTAssertEqual(initial, .imported)
        XCTAssertEqual(appended, .imported)
        XCTAssertEqual(controller.textView.string, "first\nsecond")
        let cancelled = await controller.importText("ignored", choice: .cancel)
        XCTAssertEqual(cancelled, .cancelled)
        XCTAssertEqual(controller.textView.string, "first\nsecond")

        let replaced = await controller.importText("replacement", choice: .replace)
        XCTAssertEqual(replaced, .imported)
        XCTAssertEqual(controller.textView.string, "replacement")
        let manual = store.backupsDirectory.appendingPathComponent("manual", isDirectory: true)
        let backups = try FileManager.default.contentsOfDirectory(
            at: manual, includingPropertiesForKeys: nil)
        let latest = try XCTUnwrap(backups.sorted { $0.lastPathComponent > $1.lastPathComponent }.first)
        XCTAssertEqual(
            try String(contentsOf: latest.appendingPathComponent("Pad 1.txt"), encoding: .utf8),
            "first\nsecond"
        )
        await controller.flushAll()
    }

    func testImportReplaceCancelsWhenSafetyBackupFails() async throws {
        let (controller, store, _) = try await makeController()
        controller.applyToCurrentPad("keep", replacing: true)
        controller.commitCurrentPadNow()
        await controller.flushAll()
        try? FileManager.default.removeItem(at: store.backupsDirectory)
        try Data().write(to: store.backupsDirectory)

        let result = await controller.importText("discard", choice: .replace)
        XCTAssertEqual(result, .backupFailed)
        XCTAssertEqual(controller.textView.string, "keep")
    }

    func testCurrentAndAllPadExportWorkflowsWriteCommittedText() async throws {
        let (controller, _, _) = try await makeController()
        controller.applyToCurrentPad("exported", replacing: true)
        let current = root.appendingPathComponent("current.txt")

        try controller.writeCurrentPad(to: current)
        XCTAssertEqual(try String(contentsOf: current, encoding: .utf8), "exported")
        XCTAssertThrowsError(try controller.writeCurrentPad(to: root))

        let directory = root.appendingPathComponent("all", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await controller.writeAllPads(to: directory)
        XCTAssertEqual(
            try String(contentsOf: directory.appendingPathComponent("Pad 1.txt"), encoding: .utf8),
            "exported"
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("metadata.json").path))
    }

    func testBackupAndExportWaitForEditsAcrossAllPads() async throws {
        let (controller, store, _) = try await makeController()
        controller.applyToCurrentPad("first pad latest", replacing: true)
        controller.selectPad(at: 1)
        controller.applyToCurrentPad("second pad latest", replacing: true)

        let backupCreated = await controller.makeManualBackup()
        XCTAssertTrue(backupCreated)
        let manual = store.backupsDirectory.appendingPathComponent("manual", isDirectory: true)
        let backups = try FileManager.default.contentsOfDirectory(
            at: manual, includingPropertiesForKeys: nil)
        let latest = try XCTUnwrap(backups.sorted { $0.lastPathComponent > $1.lastPathComponent }.first)
        XCTAssertEqual(
            try String(contentsOf: latest.appendingPathComponent("Pad 1.txt"), encoding: .utf8),
            "first pad latest"
        )

        let export = root.appendingPathComponent("all-latest", isDirectory: true)
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        try await controller.writeAllPads(to: export)
        XCTAssertEqual(
            try String(contentsOf: export.appendingPathComponent("Pad 1.txt"), encoding: .utf8),
            "first pad latest"
        )
        XCTAssertEqual(
            try String(contentsOf: export.appendingPathComponent("Pad 2.txt"), encoding: .utf8),
            "second pad latest"
        )
    }

    func testManualBackupWorkflowReportsSuccessAndFailure() async throws {
        let (controller, store, _) = try await makeController()
        controller.applyToCurrentPad("backup me", replacing: true)
        let created = await controller.makeManualBackup()
        XCTAssertTrue(created)

        try FileManager.default.removeItem(at: store.backupsDirectory)
        try Data().write(to: store.backupsDirectory)
        let failed = await controller.makeManualBackup()
        XCTAssertFalse(failed)
    }

    func testRestoreWorkflowRejectsEmptyFolderAndSafetyBackupFailure() async throws {
        let (controller, store, _) = try await makeController()
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let emptyResult = await controller.restoreWorkspace(from: empty)
        XCTAssertEqual(emptyResult, .noPadFiles)

        let restore = root.appendingPathComponent("restore-workflow", isDirectory: true)
        try FileManager.default.createDirectory(at: restore, withIntermediateDirectories: true)
        try "incoming".write(
            to: restore.appendingPathComponent("Pad 1.txt"), atomically: true, encoding: .utf8)
        try? FileManager.default.removeItem(at: store.backupsDirectory)
        try Data().write(to: store.backupsDirectory)

        let failedResult = await controller.restoreWorkspace(from: restore)
        XCTAssertEqual(failedResult, .safetyBackupFailed)
        XCTAssertNotEqual(controller.textView.string, "incoming")
    }

    func testRestoreWorkflowReturnsUnreadablePositionsAfterSuccessfulRestore() async throws {
        let (controller, _, _) = try await makeController()
        controller.applyToCurrentPad("old", replacing: true)
        let restore = root.appendingPathComponent("restore-success", isDirectory: true)
        try FileManager.default.createDirectory(at: restore, withIntermediateDirectories: true)
        try "incoming".write(
            to: restore.appendingPathComponent("Pad 1.txt"), atomically: true, encoding: .utf8)
        try Data([0xE9, 0xFF, 0xFE]).write(to: restore.appendingPathComponent("Pad 2.txt"))

        let result = await controller.restoreWorkspace(from: restore)
        XCTAssertEqual(result, .restored(skipped: [1]))
        XCTAssertEqual(controller.textView.string, "incoming")
        await controller.flushAll()
    }

    func testRestoreReportsPersistenceFailureAndRetainsJournal() async throws {
        let (controller, _, snapshot) = try await makeController()
        let restore = root.appendingPathComponent("restore-write-failure", isDirectory: true)
        try FileManager.default.createDirectory(at: restore, withIntermediateDirectories: true)
        try "incoming".write(
            to: restore.appendingPathComponent("Pad 1.txt"), atomically: true, encoding: .utf8)

        let padsDirectory = root.appendingPathComponent("Pads", isDirectory: true)
        try FileManager.default.removeItem(at: padsDirectory)
        try Data().write(to: padsDirectory)

        let result = await controller.restoreWorkspace(from: restore)

        XCTAssertEqual(result, .persistenceFailed)
        let selectedID = snapshot.metadata.selectedPadID.rawValue.uuidString
        let journal = root.appendingPathComponent("Journal/\(selectedID).log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: journal.path))
        XCTAssertTrue(try String(contentsOf: journal, encoding: .utf8).contains("incoming"))
    }

    private func makeController() async throws -> (PanelController, WorkspaceStore, WorkspaceSnapshot) {
        let store = WorkspaceStore(root: root)
        let snapshot = try await store.load()
        let controller = PanelController(statusItem: statusItem, store: store, snapshot: snapshot)
        return (controller, store, snapshot)
    }
}
