import Foundation

enum BackupKind: String, CaseIterable {
    case hourly
    case daily
    case manual

    // ponytail: no per-change snapshot tier — the journal plus Journal/recovered/
    // already give change-level recovery; add it only if users ask.
    var retention: Int? {
        switch self {
        case .hourly: return 24
        case .daily: return 14
        case .manual: return nil // kept until the user deletes them
        }
    }
}

extension WorkspaceStore {
    nonisolated var backupsDirectory: URL {
        backupRepositoryLocation.directory
    }

    // Backups are plain, independently readable text files (plan §9.4):
    // Backups/<kind>/<timestamp>/Pad 1.txt … Pad N.txt + workspace.json.
    @discardableResult
    func createBackup(_ kind: BackupKind) -> URL? {
        guard let metadata = currentMetadata(), prepareBackupRepository() == .ready else {
            return nil
        }
        let parent = backupsDirectory.appendingPathComponent(kind.rawValue, isDirectory: true)
        // Uniquify same-second collisions: the failure cleanup below may only
        // ever delete a directory THIS call created, never a prior backup.
        let base = Self.timestampFormatter.string(from: Date())
        var name = base
        var counter = 1
        while FileManager.default.fileExists(atPath: parent.appendingPathComponent(name).path) {
            name = "\(base)-\(counter)"
            counter += 1
        }
        let dir = parent.appendingPathComponent(name, isDirectory: true)
        let temporary = parent.appendingPathComponent(
            ".\(name)-\(UUID().uuidString).tmp",
            isDirectory: true
        )
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
            for pad in metadata.pads {
                let target = temporary.appendingPathComponent("Pad \(pad.position + 1).txt")
                let source = padURL(pad.id)
                if FileManager.default.fileExists(atPath: source.path) {
                    try FileManager.default.copyItem(at: source, to: target)
                } else {
                    try Data().write(to: target)
                }
            }
            let metadataSource = root.appendingPathComponent("workspace.json")
            if FileManager.default.fileExists(atPath: metadataSource.path) {
                try FileManager.default.copyItem(
                    at: metadataSource,
                    to: temporary.appendingPathComponent("workspace.json")
                )
            }
            try FileManager.default.moveItem(at: temporary, to: dir)
        } catch {
            let diagnostic = error as NSError
            NSLog("BetterTot: backup failed (%@:%ld)", diagnostic.domain, diagnostic.code)
            try? FileManager.default.removeItem(at: temporary)
            return nil
        }
        prune(kind)
        return dir
    }

    // Driven by write activity instead of a timer: an idle app has nothing
    // new to back up. Called after each successful commit.
    func autoBackupIfDue(now: Date = Date()) {
        if age(ofNewest: .hourly, at: now) > 3600 { createBackup(.hourly) }
        if age(ofNewest: .daily, at: now) > 86400 { createBackup(.daily) }
    }

    func backupCounts() -> [BackupKind: Int] {
        guard prepareBackupRepository() == .ready else { return [:] }
        var counts: [BackupKind: Int] = [:]
        for kind in BackupKind.allCases {
            counts[kind] = backupDirs(kind).count
        }
        return counts
    }

    func backupRepositorySummary() -> BackupRepositorySummary {
        let health = prepareBackupRepository()
        guard health == .ready else {
            return BackupRepositorySummary(
                health: health,
                directory: backupsDirectory,
                canOpenDirectory: isPlainBackupDirectory(backupsDirectory),
                latestBackupDate: nil,
                latestBackupSizeBytes: nil,
                counts: [:]
            )
        }

        let directories = BackupKind.allCases.flatMap { kind in
            backupDirs(kind).map { (kind, $0) }
        }
        let latest = directories.max { lhs, rhs in
            let left = timestampDate(of: lhs.1.lastPathComponent) ?? .distantPast
            let right = timestampDate(of: rhs.1.lastPathComponent) ?? .distantPast
            return left < right
        }
        let counts = Dictionary(uniqueKeysWithValues: BackupKind.allCases.map {
            ($0, backupDirs($0).count)
        })
        return BackupRepositorySummary(
            health: .ready,
            directory: backupsDirectory,
            canOpenDirectory: true,
            latestBackupDate: latest.flatMap { timestampDate(of: $0.1.lastPathComponent) },
            latestBackupSizeBytes: latest.map { directorySize($0.1) },
            counts: counts
        )
    }

    func exportAllPads(to directory: URL) throws {
        guard let metadata = currentMetadata() else { return }
        for pad in metadata.pads {
            let target = directory.appendingPathComponent("Pad \(pad.position + 1).txt")
            let source = padURL(pad.id)
            if FileManager.default.fileExists(atPath: source.path) {
                let data = try Data(contentsOf: source)
                try data.write(to: target, options: .atomic)
            } else {
                try Data().write(to: target, options: .atomic)
            }
        }
        let metadataSource = root.appendingPathComponent("workspace.json")
        if FileManager.default.fileExists(atPath: metadataSource.path) {
            let data = try Data(contentsOf: metadataSource)
            try data.write(to: directory.appendingPathComponent("metadata.json"), options: .atomic)
        }
    }

    // MARK: - Internals

    // Accepts "yyyyMMdd-HHmmss" plus an optional collision suffix ("-1", …).
    private func timestampDate(of name: String) -> Date? {
        Self.timestampFormatter.date(from: String(name.prefix(15)))
    }

    private func prepareBackupRepository() -> BackupRepositoryHealth {
        BackupRepositoryValidation.prepare(
            backupRepositoryLocationResolver?.resolve() ?? backupRepositoryLocation
        )
    }

    private func isPlainBackupDirectory(_ directory: URL) -> Bool {
        guard let values = try? directory.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    func migrateLegacyBackupsIfNeeded() {
        guard prepareBackupRepository() == .ready else { return }
        let migrationRecord = backupsDirectory.appendingPathComponent(
            LegacyBackupMigrationRecord.fileName
        )
        guard !FileManager.default.fileExists(atPath: migrationRecord.path) else { return }
        var completed = true
        for legacyRoot in legacyBackupDirectories {
            let sourceRoot = legacyRoot.standardizedFileURL
            guard sourceRoot != backupsDirectory.standardizedFileURL else { continue }
            for kind in BackupKind.allCases {
                let sourceTier = sourceRoot.appendingPathComponent(kind.rawValue, isDirectory: true)
                let sources = backupDirectories(in: sourceTier)
                for source in sources.reversed() {
                    if !migrateLegacyBackup(source, kind: kind) {
                        completed = false
                    }
                }
            }
        }
        guard completed else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let record = LegacyBackupMigrationRecord(schemaVersion: 1, completedAt: Date())
            try encoder.encode(record).write(to: migrationRecord, options: .atomic)
        } catch {
            let diagnostic = error as NSError
            NSLog(
                "BetterTot: backup migration record failed (%@:%ld)",
                diagnostic.domain,
                diagnostic.code
            )
        }
    }

    private func migrateLegacyBackup(_ source: URL, kind: BackupKind) -> Bool {
        guard isSafeLegacySnapshot(source) else {
            NSLog("BetterTot: skipped malformed legacy backup during migration")
            return true
        }
        let tier = backupsDirectory.appendingPathComponent(kind.rawValue, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tier, withIntermediateDirectories: true)
            var destination = tier.appendingPathComponent(
                source.lastPathComponent,
                isDirectory: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                guard !directoriesMatch(source, destination) else { return true }
                var suffix = 1
                repeat {
                    destination = tier.appendingPathComponent(
                        "\(source.lastPathComponent)-migrated-\(suffix)",
                        isDirectory: true
                    )
                    suffix += 1
                } while FileManager.default.fileExists(atPath: destination.path)
            }
            let temporary = tier.appendingPathComponent(
                ".migration-\(UUID().uuidString).tmp",
                isDirectory: true
            )
            do {
                try FileManager.default.copyItem(at: source, to: temporary)
                try FileManager.default.moveItem(at: temporary, to: destination)
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                throw error
            }
            return true
        } catch {
            let diagnostic = error as NSError
            NSLog(
                "BetterTot: legacy backup migration failed (%@:%ld)",
                diagnostic.domain,
                diagnostic.code
            )
            return false
        }
    }

    private func backupDirectories(in tier: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: tier,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: .skipsHiddenFiles
        )) ?? []
        return contents.filter {
            guard timestampDate(of: $0.lastPathComponent) != nil,
                  let values = try? $0.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isSymbolicLinkKey,
                  ]) else { return false }
            return values.isDirectory == true && values.isSymbolicLink != true
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    private func isSafeLegacySnapshot(_ directory: URL) -> Bool {
        let allowed = Set(
            (1...WorkspaceMetadata.compatibleBackupPadCount).map { "Pad \($0).txt" }
                + ["workspace.json", ".bettertot-backup"]
        )
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else { return false }
        return files.allSatisfy { file in
            guard allowed.contains(file.lastPathComponent),
                  let values = try? file.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                  ]) else { return false }
            return values.isRegularFile == true && values.isSymbolicLink != true
        }
    }

    private func directorySize(_ directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private func directoriesMatch(_ lhs: URL, _ rhs: URL) -> Bool {
        func files(in root: URL) -> [String: Data]? {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else { return nil }
            var result: [String: Data] = [:]
            for case let file as URL in enumerator {
                guard let values = try? file.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ]),
                values.isRegularFile == true,
                values.isSymbolicLink != true,
                let data = try? Data(contentsOf: file) else { continue }
                let relative = String(file.path.dropFirst(root.path.count + 1))
                result[relative] = data
            }
            return result
        }
        guard let left = files(in: lhs), let right = files(in: rhs) else { return false }
        return left == right
    }

    // Only timestamp-named directories are ours to count, age, or prune —
    // anything a user dropped or renamed in here is invisible and untouchable.
    private func backupDirs(_ kind: BackupKind) -> [URL] {
        let dir = backupsDirectory.appendingPathComponent(kind.rawValue, isDirectory: true)
        return backupDirectories(in: dir)
    }

    private func age(ofNewest kind: BackupKind, at now: Date) -> TimeInterval {
        guard let newest = backupDirs(kind).first,
              let date = timestampDate(of: newest.lastPathComponent) else {
            return .infinity
        }
        return now.timeIntervalSince(date)
    }

    private func prune(_ kind: BackupKind) {
        guard let keep = kind.retention else { return }
        for stale in backupDirs(kind).dropFirst(keep) {
            try? FileManager.default.removeItem(at: stale)
        }
    }

    // Sortable, Finder-safe timestamps (no colons).
    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
