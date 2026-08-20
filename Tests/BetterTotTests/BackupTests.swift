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

    func testICloudResolverUsesDeterministicAppFolder() throws {
        let cloudDrive = root.appendingPathComponent("CloudDocs", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudDrive, withIntermediateDirectories: true)
        let resolver = PrivateICloudDriveBackupLocationResolver(cloudDriveRoot: cloudDrive)

        let location = resolver.resolve()

        XCTAssertEqual(
            location.directory,
            cloudDrive.appendingPathComponent(
                "BetterTot Backups (org.bettertot.BetterTot)",
                isDirectory: true
            )
        )
        XCTAssertTrue(location.isAvailable)
    }

    func testUnavailableICloudNeverFallsBackToLocalBackups() async throws {
        let missingCloudDrive = root.appendingPathComponent("Missing CloudDocs", isDirectory: true)
        let location = PrivateICloudDriveBackupLocationResolver(
            cloudDriveRoot: missingCloudDrive
        ).resolve()
        let localData = root.appendingPathComponent("Application Support", isDirectory: true)
        let store = WorkspaceStore(root: localData, backupRepositoryLocation: location)
        let snapshot = try await store.load()

        await store.commit(snapshot.metadata.pads[0].id, text: "still saved", revision: 1)
        let backup = await store.createBackup(.manual)

        XCTAssertNil(backup)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: localData.appendingPathComponent("Backups").path
        ))
        XCTAssertEqual(
            try String(contentsOf: await store.padURL(snapshot.metadata.pads[0].id)),
            "still saved"
        )
    }

    func testICloudAvailabilityIsRecheckedWithoutRelaunching() async throws {
        let cloudDrive = root.appendingPathComponent("CloudDocs", isDirectory: true)
        let resolver = PrivateICloudDriveBackupLocationResolver(
            cloudDriveRoot: cloudDrive
        )
        let store = WorkspaceStore(
            root: root.appendingPathComponent("Application Support"),
            backupRepositoryLocationResolver: resolver
        )

        let unavailable = await store.backupRepositorySummary()
        guard case .unavailable = unavailable.health else {
            return XCTFail("Missing iCloud Drive must initially be unavailable")
        }

        try FileManager.default.createDirectory(
            at: cloudDrive,
            withIntermediateDirectories: true
        )
        let recovered = await store.backupRepositorySummary()

        XCTAssertEqual(recovered.health, .ready)
        XCTAssertEqual(recovered.directory, resolver.resolve().directory)
    }

    func testICloudRepositoryReportsLatestBackupTimeAndSize() async throws {
        let cloudDrive = root.appendingPathComponent("CloudDocs", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudDrive, withIntermediateDirectories: true)
        let location = PrivateICloudDriveBackupLocationResolver(
            cloudDriveRoot: cloudDrive
        ).resolve()
        let localData = root.appendingPathComponent("Application Support", isDirectory: true)
        let store = WorkspaceStore(root: localData, backupRepositoryLocation: location)
        let snapshot = try await store.load()
        await store.commit(snapshot.metadata.pads[0].id, text: "cloud only", revision: 1)

        let created = await store.createBackup(.manual)
        let summary = await store.backupRepositorySummary()

        XCTAssertNotNil(created)
        XCTAssertEqual(summary.health, .ready)
        XCTAssertNotNil(summary.latestBackupDate)
        XCTAssertGreaterThan(summary.latestBackupSizeBytes ?? 0, 0)
        XCTAssertEqual(summary.totalCount, 3)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: localData.appendingPathComponent("Backups").path
        ))
    }

    func testForeignICloudRepositoryContentBlocksWritesWithoutMutation() async throws {
        let cloudDrive = root.appendingPathComponent("CloudDocs", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudDrive, withIntermediateDirectories: true)
        let location = PrivateICloudDriveBackupLocationResolver(
            cloudDriveRoot: cloudDrive
        ).resolve()
        try FileManager.default.createDirectory(
            at: location.directory,
            withIntermediateDirectories: false
        )
        let foreign = location.directory.appendingPathComponent("personal.txt")
        try Data("do not touch".utf8).write(to: foreign)
        let store = WorkspaceStore(
            root: root.appendingPathComponent("Application Support"),
            backupRepositoryLocation: location
        )
        _ = try await store.load()

        let created = await store.createBackup(.manual)
        let summary = await store.backupRepositorySummary()

        XCTAssertNil(created)
        guard case .blocked = summary.health else {
            return XCTFail("Foreign content must block the repository")
        }
        XCTAssertTrue(summary.canOpenDirectory)
        XCTAssertEqual(try Data(contentsOf: foreign), Data("do not touch".utf8))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: location.directory.path),
            ["personal.txt"]
        )
    }

    func testSymlinkedRepositoryIsBlockedAndCannotBeOpenedAsTrustedLocation() async throws {
        let cloudDrive = root.appendingPathComponent("CloudDocs", isDirectory: true)
        let target = root.appendingPathComponent("Foreign Target", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudDrive, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let location = PrivateICloudDriveBackupLocationResolver(
            cloudDriveRoot: cloudDrive
        ).resolve()
        try FileManager.default.createSymbolicLink(
            at: location.directory,
            withDestinationURL: target
        )
        let store = WorkspaceStore(
            root: root.appendingPathComponent("Application Support"),
            backupRepositoryLocation: location
        )
        _ = try await store.load()

        let summary = await store.backupRepositorySummary()

        guard case .blocked = summary.health else {
            return XCTFail("A symlinked repository must be blocked")
        }
        XCTAssertFalse(summary.canOpenDirectory)
        let blockedBackup = await store.createBackup(.manual)
        XCTAssertNil(blockedBackup)
    }

    func testSymlinkedRepositoryManifestIsBlockedWithoutFollowingIt() async throws {
        let cloudDrive = root.appendingPathComponent("CloudDocs", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudDrive, withIntermediateDirectories: true)
        let location = PrivateICloudDriveBackupLocationResolver(
            cloudDriveRoot: cloudDrive
        ).resolve()
        try FileManager.default.createDirectory(
            at: location.directory,
            withIntermediateDirectories: false
        )
        let target = root.appendingPathComponent("foreign-repository.json")
        try JSONEncoder().encode(BackupRepositoryManifest.current).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: location.directory.appendingPathComponent(BackupRepositoryManifest.fileName),
            withDestinationURL: target
        )
        let store = WorkspaceStore(
            root: root.appendingPathComponent("Application Support"),
            backupRepositoryLocation: location
        )

        let summary = await store.backupRepositorySummary()

        guard case .blocked = summary.health else {
            return XCTFail("A symlinked repository manifest must be blocked")
        }
        XCTAssertEqual(
            try JSONDecoder().decode(
                BackupRepositoryManifest.self,
                from: Data(contentsOf: target)
            ),
            .current
        )
    }

    func testLegacyLocalBackupsMigrateToICloudWithoutDeletingSource() async throws {
        let legacy = root.appendingPathComponent("Legacy Backups", isDirectory: true)
        let legacySnapshot = legacy.appendingPathComponent(
            "manual/20260102-030405",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacySnapshot,
            withIntermediateDirectories: true
        )
        try Data("legacy note".utf8).write(
            to: legacySnapshot.appendingPathComponent("Pad 1.txt")
        )
        let cloudDrive = root.appendingPathComponent("CloudDocs", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudDrive, withIntermediateDirectories: true)
        let location = PrivateICloudDriveBackupLocationResolver(
            cloudDriveRoot: cloudDrive
        ).resolve()
        let store = WorkspaceStore(
            root: root.appendingPathComponent("Application Support"),
            backupRepositoryLocation: location,
            legacyBackupDirectories: [legacy]
        )

        _ = try await store.load()
        let summary = await store.backupRepositorySummary()
        let migrated = location.directory.appendingPathComponent(
            "manual/20260102-030405/Pad 1.txt"
        )

        XCTAssertEqual(summary.totalCount, 1)
        XCTAssertEqual(try Data(contentsOf: migrated), Data("legacy note".utf8))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: legacySnapshot.appendingPathComponent("Pad 1.txt").path
        ))
    }

    func testMalformedLegacySnapshotIsNotMigrated() async throws {
        let legacy = root.appendingPathComponent("Legacy Backups", isDirectory: true)
        let legacySnapshot = legacy.appendingPathComponent(
            "manual/20260102-030405",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacySnapshot,
            withIntermediateDirectories: true
        )
        let foreign = legacySnapshot.appendingPathComponent("foreign.txt")
        try Data("leave here".utf8).write(to: foreign)
        let cloudDrive = root.appendingPathComponent("CloudDocs", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudDrive, withIntermediateDirectories: true)
        let location = PrivateICloudDriveBackupLocationResolver(
            cloudDriveRoot: cloudDrive
        ).resolve()
        let store = WorkspaceStore(
            root: root.appendingPathComponent("Application Support"),
            backupRepositoryLocation: location,
            legacyBackupDirectories: [legacy]
        )

        _ = try await store.load()
        let summary = await store.backupRepositorySummary()

        XCTAssertEqual(summary.totalCount, 0)
        XCTAssertEqual(try Data(contentsOf: foreign), Data("leave here".utf8))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: location.directory.appendingPathComponent(
                "manual/20260102-030405"
            ).path
        ))
    }

    func testCompletedMigrationDoesNotResurrectDeletedBackupOnRelaunch() async throws {
        let legacy = root.appendingPathComponent("Legacy Backups", isDirectory: true)
        let legacySnapshot = legacy.appendingPathComponent(
            "manual/20260102-030405",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: legacySnapshot,
            withIntermediateDirectories: true
        )
        try Data("legacy".utf8).write(
            to: legacySnapshot.appendingPathComponent("Pad 1.txt")
        )
        let cloudDrive = root.appendingPathComponent("CloudDocs", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudDrive, withIntermediateDirectories: true)
        let location = PrivateICloudDriveBackupLocationResolver(
            cloudDriveRoot: cloudDrive
        ).resolve()
        let localData = root.appendingPathComponent("Application Support")
        let firstStore = WorkspaceStore(
            root: localData,
            backupRepositoryLocation: location,
            legacyBackupDirectories: [legacy]
        )
        _ = try await firstStore.load()
        let migrated = location.directory.appendingPathComponent(
            "manual/20260102-030405",
            isDirectory: true
        )
        try FileManager.default.removeItem(at: migrated)

        let relaunchedStore = WorkspaceStore(
            root: localData,
            backupRepositoryLocation: location,
            legacyBackupDirectories: [legacy]
        )
        _ = try await relaunchedStore.load()

        XCTAssertFalse(FileManager.default.fileExists(atPath: migrated.path))
        let relaunchedSummary = await relaunchedStore.backupRepositorySummary()
        XCTAssertEqual(relaunchedSummary.totalCount, 0)
    }

    func testKnownFinderMetadataDoesNotBlockRepository() async throws {
        let cloudDrive = root.appendingPathComponent("CloudDocs", isDirectory: true)
        try FileManager.default.createDirectory(at: cloudDrive, withIntermediateDirectories: true)
        let location = PrivateICloudDriveBackupLocationResolver(
            cloudDriveRoot: cloudDrive
        ).resolve()
        let snapshot = location.directory.appendingPathComponent(
            "manual/20260102-030405",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try Data().write(to: location.directory.appendingPathComponent(".DS_Store"))
        try Data().write(to: snapshot.appendingPathComponent(".DS_Store"))
        let store = WorkspaceStore(
            root: root.appendingPathComponent("Application Support"),
            backupRepositoryLocation: location
        )

        _ = try await store.load()
        let summary = await store.backupRepositorySummary()

        XCTAssertEqual(summary.health, .ready)
        XCTAssertEqual(summary.totalCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: location.directory.appendingPathComponent(".DS_Store").path
        ))
    }

    func testManualBackupContainsAllPadsAsReadableText() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        await store.commit(snapshot.metadata.pads[0].id, text: "first pad", revision: 1)
        await store.commit(snapshot.metadata.pads[2].id, text: "third pad 🙂", revision: 1)

        let dir = await store.createBackup(.manual)
        let backupDir = try XCTUnwrap(dir)

        for position in 1...WorkspaceMetadata.padCount {
            let file = backupDir.appendingPathComponent("Pad \(position).txt")
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                          "backup always contains every pad file")
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

    func testStrayFolderInBackupTierBlocksWritesWithoutBeingDeleted() async throws {
        let store = makeStore()
        let snapshot = try await store.load()
        let stray = store.backupsDirectory.appendingPathComponent("hourly/untitled folder")
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)

        let id = snapshot.metadata.pads[0].id
        await store.commit(id, text: "one", revision: 1)
        await store.commit(id, text: "two", revision: 2)
        let summary = await store.backupRepositorySummary()

        let hourly = try FileManager.default.contentsOfDirectory(
            at: store.backupsDirectory.appendingPathComponent("hourly"),
            includingPropertiesForKeys: nil).map(\.lastPathComponent)
        XCTAssertEqual(hourly, ["untitled folder"])
        XCTAssertTrue(hourly.contains("untitled folder"), "user folders are never deleted")
        guard case .blocked = summary.health else {
            return XCTFail("Invalid tier content must block backup writes")
        }
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
        let expected = (1...WorkspaceMetadata.padCount).map { "Pad \($0).txt" }
            + ["metadata.json"]
        XCTAssertEqual(contents, expected.sorted())
        XCTAssertEqual(
            try String(contentsOf: exportDir.appendingPathComponent("Pad 2.txt"), encoding: .utf8),
            "export me")
    }
}
