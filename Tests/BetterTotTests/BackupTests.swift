import XCTest
@testable import BetterTot

final class BackupTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bettertot-backup-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(root: root)
    }

    func testManualBackupContainsAllPadsAsReadableText() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        await store.commit(snapshot.metadata.pads[0].id, text: "first pad", revision: 1)
        await store.commit(snapshot.metadata.pads[2].id, text: "third pad 🙂", revision: 1)

        let dir = await store.createBackup(.manual)
        let backupDir = try XCTUnwrap(dir)

        for position in 1...7 {
            let file = backupDir.appendingPathComponent("Pad \(position).txt")
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                          "backup always contains all seven pad files")
        }
        XCTAssertEqual(
            try String(contentsOf: backupDir.appendingPathComponent("Pad 1.txt"), encoding: .utf8),
            "first pad")
        XCTAssertEqual(
            try String(contentsOf: backupDir.appendingPathComponent("Pad 3.txt"), encoding: .utf8),
            "third pad 🙂")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: backupDir.appendingPathComponent("workspace.json").path))
    }

    func testHourlyPruningKeepsNewest24ManualKeepsAll() async throws {
        let store = makeStore()
        _ = try await store.load()
        // 30 old backups per kind with PARSEABLE timestamp names
        let hourlyDir = store.backupsDirectory.appendingPathComponent("hourly")
        let manualDir = store.backupsDirectory.appendingPathComponent("manual")
        var stamps: [String] = []
        for index in 0..<30 {
            let stamp = String(format: "20250101-%02d%02d00", index / 60, index % 60)
            stamps.append(stamp)
            try FileManager.default.createDirectory(
                at: hourlyDir.appendingPathComponent(stamp), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: manualDir.appendingPathComponent(stamp), withIntermediateDirectories: true)
        }

        // a new hourly backup triggers pruning of that kind only
        let created = await store.createBackup(.hourly)
        let newDir = try XCTUnwrap(created)

        let hourlySurvivors = try FileManager.default.contentsOfDirectory(
            at: hourlyDir, includingPropertiesForKeys: nil).map(\.lastPathComponent)
        let manualCount = try FileManager.default.contentsOfDirectory(
            at: manualDir, includingPropertiesForKeys: nil).count
        XCTAssertEqual(hourlySurvivors.count, 24, "hourly retention keeps 24")
        XCTAssertEqual(manualCount, 30, "manual backups are never pruned")
        // the NEWEST survive: the just-created dir plus the 23 newest fixtures
        XCTAssertTrue(hourlySurvivors.contains(newDir.lastPathComponent),
                      "the backup just created must survive its own prune")
        for stamp in stamps.suffix(23) {
            XCTAssertTrue(hourlySurvivors.contains(stamp), "newest fixtures survive")
        }
        for stamp in stamps.prefix(7) {
            XCTAssertFalse(hourlySurvivors.contains(stamp), "oldest fixtures pruned")
        }
    }

    func testSameSecondBackupsBothSurvive() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        await store.commit(snapshot.metadata.pads[0].id, text: "precious", revision: 1)

        let first = await store.createBackup(.manual)
        let second = await store.createBackup(.manual)
        let firstDir = try XCTUnwrap(first)
        let secondDir = try XCTUnwrap(second, "same-second backup must not fail")
        XCTAssertNotEqual(firstDir, secondDir, "collision is uniquified, not clobbered")
        for dir in [firstDir, secondDir] {
            XCTAssertEqual(
                try String(contentsOf: dir.appendingPathComponent("Pad 1.txt"), encoding: .utf8),
                "precious",
                "both backups remain intact")
        }
    }

    func testStrayFolderInHourlyDoesNotDefeatStalenessOrGetPruned() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let stray = store.backupsDirectory.appendingPathComponent("hourly/untitled folder")
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)

        let id = snapshot.metadata.pads[0].id
        await store.commit(id, text: "one", revision: 1)
        await store.commit(id, text: "two", revision: 2)

        let hourly = try FileManager.default.contentsOfDirectory(
            at: store.backupsDirectory.appendingPathComponent("hourly"),
            includingPropertiesForKeys: nil).map(\.lastPathComponent)
        XCTAssertEqual(hourly.count, 2, "stray + exactly one real hourly backup")
        XCTAssertTrue(hourly.contains("untitled folder"), "user folders are never deleted")
    }

    func testDailyTierTriggersWhenStaleAndPrunesTo14() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        await store.commit(snapshot.metadata.pads[0].id, text: "seed", revision: 1)
        // 15 old parseable daily backups
        let dailyDir = store.backupsDirectory.appendingPathComponent("daily")
        try? FileManager.default.removeItem(at: dailyDir) // drop the auto-created one
        for index in 0..<15 {
            try FileManager.default.createDirectory(
                at: dailyDir.appendingPathComponent(String(format: "20250101-0000%02d", index)),
                withIntermediateDirectories: true)
        }

        await store.autoBackupIfDue() // newest daily is a year stale
        let daily = try FileManager.default.contentsOfDirectory(
            at: dailyDir, includingPropertiesForKeys: nil).map(\.lastPathComponent).sorted()
        XCTAssertEqual(daily.count, 14, "daily retention keeps 14 including the new one")
        XCTAssertFalse(daily.contains("20250101-000000"), "oldest fixtures pruned first")
        XCTAssertFalse(daily.contains("20250101-000001"))
        XCTAssertTrue(daily.last?.hasPrefix("2025") == false, "a fresh daily backup was created")
    }

    func testCommitTriggersHourlyBackupOnlyWhenStale() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let id = snapshot.metadata.pads[0].id
        await store.commit(id, text: "one", revision: 1)
        await store.commit(id, text: "two", revision: 2)
        await store.commit(id, text: "three", revision: 3)

        let hourly = try FileManager.default.contentsOfDirectory(
            at: store.backupsDirectory.appendingPathComponent("hourly"),
            includingPropertiesForKeys: nil)
        XCTAssertEqual(hourly.count, 1, "rapid commits share one fresh hourly backup")
    }

    func testExportAllPadsWritesReadableLayout() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        await store.commit(snapshot.metadata.pads[1].id, text: "export me", revision: 1)
        let exportDir = root.appendingPathComponent("export-target")
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        try await store.exportAllPads(to: exportDir)

        let contents = try FileManager.default.contentsOfDirectory(
            at: exportDir, includingPropertiesForKeys: nil).map(\.lastPathComponent).sorted()
        XCTAssertEqual(contents, [
            "Pad 1.txt", "Pad 2.txt", "Pad 3.txt", "Pad 4.txt",
            "Pad 5.txt", "Pad 6.txt", "Pad 7.txt", "metadata.json",
        ].sorted())
        XCTAssertEqual(
            try String(contentsOf: exportDir.appendingPathComponent("Pad 2.txt"), encoding: .utf8),
            "export me")
    }
}
