import AppKit
import XCTest
@testable import BetterTot

// Headless round trip of PanelController.restore(from:) — the code enforcing
// the per-position "Pad N.txt" mapping behind the no-cross-contamination
// requirement. AppKit objects construct fine inside xctest on macOS.
@MainActor
final class RestoreTests: XCTestCase {
    private var root: URL!
    private var statusItem: NSStatusItem!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettertot-restore-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    }

    override func tearDown() async throws {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        try? FileManager.default.removeItem(at: root)
    }

    func testRestoreMapsFilesToPadsByPositionAndSkipsMissing() async throws {
        let store = WorkspaceStore(root: root)
        let snapshot = try await store.load()
        let controller = PanelController(statusItem: statusItem, store: store, snapshot: snapshot)

        // a backup directory: pads 1 and 3 present, everything else absent
        let backupDir = root.appendingPathComponent("fake-backup")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        try "restored one".write(
            to: backupDir.appendingPathComponent("Pad 1.txt"), atomically: true, encoding: .utf8)
        try "restored three".write(
            to: backupDir.appendingPathComponent("Pad 3.txt"), atomically: true, encoding: .utf8)

        // current content that must survive where the backup has no file
        let pads = snapshot.metadata.pads.sorted { $0.position < $1.position }
        await store.commit(pads[1].id, text: "keep me", revision: 1)

        let padFiles = (1...WorkspaceMetadata.padCount).map {
            backupDir.appendingPathComponent("Pad \($0).txt")
        }
        let skipped = await controller.restore(from: padFiles)
        XCTAssertEqual(skipped, [], "missing files are skipped silently, not reported")

        let reloaded = try await WorkspaceStore(root: root).load()
        let reloadedPads = reloaded.metadata.pads.sorted { $0.position < $1.position }
        XCTAssertEqual(reloaded.texts[reloadedPads[0].id], "restored one")
        XCTAssertEqual(reloaded.texts[reloadedPads[1].id], "keep me",
                       "pad without a backup file keeps its current content")
        XCTAssertEqual(reloaded.texts[reloadedPads[2].id], "restored three",
                       "no cross-contamination: each file lands on its own position")
    }

    func testRestoreReportsUnreadableExistingFiles() async throws {
        let store = WorkspaceStore(root: root)
        let snapshot = try await store.load()
        let controller = PanelController(statusItem: statusItem, store: store, snapshot: snapshot)

        let backupDir = root.appendingPathComponent("fake-backup")
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        try "fine".write(
            to: backupDir.appendingPathComponent("Pad 1.txt"), atomically: true, encoding: .utf8)
        // exists but is not decodable text (invalid UTF-8, no encoding attr)
        try Data([0xE9, 0xFF, 0xFE]).write(to: backupDir.appendingPathComponent("Pad 2.txt"))

        let padFiles = (1...WorkspaceMetadata.padCount).map {
            backupDir.appendingPathComponent("Pad \($0).txt")
        }
        let skipped = await controller.restore(from: padFiles)
        XCTAssertEqual(skipped, [1], "existing-but-unreadable file is reported by position index")
    }
}
