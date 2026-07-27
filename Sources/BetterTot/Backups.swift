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
        root.appendingPathComponent("Backups", isDirectory: true)
    }

    // Backups are plain, independently readable text files (plan §9.4):
    // Backups/<kind>/<timestamp>/Pad 1.txt … Pad 7.txt + workspace.json.
    @discardableResult
    func createBackup(_ kind: BackupKind) -> URL? {
        guard let metadata = currentMetadata() else { return nil }
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
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for pad in metadata.pads {
                let target = dir.appendingPathComponent("Pad \(pad.position + 1).txt")
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
                    at: metadataSource, to: dir.appendingPathComponent("workspace.json"))
            }
        } catch {
            let diagnostic = error as NSError
            NSLog("BetterTot: backup failed (%@:%ld)", diagnostic.domain, diagnostic.code)
            try? FileManager.default.removeItem(at: dir)
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
        var counts: [BackupKind: Int] = [:]
        for kind in BackupKind.allCases {
            counts[kind] = backupDirs(kind).count
        }
        return counts
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

    // Only timestamp-named directories are ours to count, age, or prune —
    // anything a user dropped or renamed in here is invisible and untouchable.
    private func backupDirs(_ kind: BackupKind) -> [URL] {
        let dir = backupsDirectory.appendingPathComponent(kind.rawValue, isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return contents
            .filter { $0.hasDirectoryPath && timestampDate(of: $0.lastPathComponent) != nil }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // newest first
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
