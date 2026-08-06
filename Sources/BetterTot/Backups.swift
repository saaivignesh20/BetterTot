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

struct BackupMirrorStatus: Equatable, Sendable {
    let directory: URL?
    let errorDescription: String?
}

actor BackupMirrorService {
    private static let ownershipMarker = ".bettertot-backup"
    private let localBackupsDirectory: URL
    private let copyItem: @Sendable (URL, URL) throws -> Void
    private var parentDirectory: URL?
    private var errorDescription: String?
    private var backfilledDirectory: URL?

    init(
        parentDirectory: URL?,
        localBackupsDirectory: URL,
        copyItem: @escaping @Sendable (URL, URL) throws -> Void = {
            try FileManager.default.copyItem(at: $0, to: $1)
        }
    ) {
        self.parentDirectory = parentDirectory?.standardizedFileURL
        self.localBackupsDirectory = localBackupsDirectory
        self.copyItem = copyItem
    }

    func configure(
        at directory: URL?,
        snapshots: [BackupKind: [URL]]
    ) -> BackupMirrorStatus {
        let normalized = directory?.standardizedFileURL
        let destinationChanged = normalized != parentDirectory
        let shouldRetry = errorDescription != nil
        if destinationChanged {
            backfilledDirectory = nil
        }
        parentDirectory = normalized
        guard normalized != nil else {
            errorDescription = nil
            backfilledDirectory = nil
            return status()
        }
        guard let mirrorRoot = validatedRoot() else { return status() }
        guard backfilledDirectory != mirrorRoot
                || shouldRetry
                || !FileManager.default.fileExists(atPath: mirrorRoot.path) else {
            return status()
        }
        errorDescription = nil
        guard !Task.isCancelled else { return cancelConfiguration() }

        do {
            try FileManager.default.createDirectory(
                at: mirrorRoot,
                withIntermediateDirectories: true
            )
            for kind in BackupKind.allCases {
                for source in (snapshots[kind] ?? []).reversed() {
                    guard !Task.isCancelled else { return cancelConfiguration() }
                    try copyIfNeeded(kind, source: source, root: mirrorRoot)
                }
                try prune(kind, root: mirrorRoot)
            }
            backfilledDirectory = mirrorRoot
        } catch is CancellationError {
            return cancelConfiguration()
        } catch {
            recordFailure(error)
        }
        return status()
    }

    private func cancelConfiguration() -> BackupMirrorStatus {
        parentDirectory = nil
        backfilledDirectory = nil
        errorDescription = nil
        return status()
    }

    func mirror(_ kind: BackupKind, source: URL) {
        guard !Task.isCancelled, let mirrorRoot = validatedRoot() else { return }
        do {
            try copyIfNeeded(kind, source: source, root: mirrorRoot)
            try prune(kind, root: mirrorRoot)
            errorDescription = nil
        } catch is CancellationError {
            return
        } catch {
            recordFailure(error)
        }
    }

    func status() -> BackupMirrorStatus {
        BackupMirrorStatus(
            directory: validatedRoot(),
            errorDescription: errorDescription
        )
    }

    private func copyIfNeeded(_ kind: BackupKind, source: URL, root: URL) throws {
        let parent = root.appendingPathComponent(kind.rawValue, isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let destination = parent.appendingPathComponent(
            source.lastPathComponent,
            isDirectory: true
        )
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }

        let temporary = parent.appendingPathComponent(
            ".\(source.lastPathComponent)-\(UUID().uuidString).tmp",
            isDirectory: true
        )
        do {
            try copyItem(source, temporary)
            try Task.checkCancellation()
            try Data().write(
                to: temporary.appendingPathComponent(Self.ownershipMarker),
                options: .atomic
            )
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private func prune(_ kind: BackupKind, root: URL) throws {
        guard let keep = kind.retention else { return }
        let parent = root.appendingPathComponent(kind.rawValue, isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: parent,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )) ?? []
        let snapshots = contents
            .filter {
                $0.hasDirectoryPath
                    && Self.isBackupDirectoryName($0.lastPathComponent)
                    && FileManager.default.fileExists(
                        atPath: $0.appendingPathComponent(Self.ownershipMarker).path
                    )
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for stale in snapshots.dropFirst(keep) {
            try FileManager.default.removeItem(at: stale)
        }
    }

    private func validatedRoot() -> URL? {
        guard let configuredParent = parentDirectory,
              configuredParent.isFileURL,
              configuredParent.path != "/" else {
            return nil
        }
        let parent = configuredParent.resolvingSymlinksInPath().standardizedFileURL
        let mirrorRoot = parent.appendingPathComponent("BetterTot Backups", isDirectory: true)
            .standardizedFileURL
        let localRoot = localBackupsDirectory.resolvingSymlinksInPath().standardizedFileURL
        let localPrefix = localRoot.path + "/"
        guard mirrorRoot != localRoot,
              !mirrorRoot.path.hasPrefix(localPrefix) else {
            errorDescription = "Choose a folder outside BetterTot's local backups."
            return nil
        }
        return mirrorRoot
    }

    private func recordFailure(_ error: Error) {
        let diagnostic = error as NSError
        errorDescription = error.localizedDescription
        NSLog(
            "BetterTot: backup mirror failed (%@:%ld)",
            diagnostic.domain,
            diagnostic.code
        )
    }

    private static func isBackupDirectoryName(_ name: String) -> Bool {
        let parts = name.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              parts[0].count == 8,
              parts[1].count == 6,
              Self.isASCIIDigits(parts[0]),
              Self.isASCIIDigits(parts[1]),
              parts.count == 2 || Self.isASCIIDigits(parts[2]) else {
            return false
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.isLenient = false
        return formatter.date(from: "\(parts[0])-\(parts[1])") != nil
    }

    private static func isASCIIDigits(_ value: Substring) -> Bool {
        !value.isEmpty && value.utf8.allSatisfy { (48...57).contains($0) }
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
        enqueueBackupMirror(kind, source: dir)
        return dir
    }

    func configureBackupMirror(at directory: URL?) async -> BackupMirrorStatus {
        backupMirrorConfigurationGeneration &+= 1
        let generation = backupMirrorConfigurationGeneration
        backupMirrorReconfigurationGeneration = generation

        let pending = Array(pendingBackupMirrorTasks.values)
        pendingBackupMirrorTasks.removeAll()
        pending.forEach { $0.cancel() }
        for task in pending {
            await task.value
        }
        guard backupMirrorReconfigurationGeneration == generation else {
            return await backupMirror.status()
        }

        let status: BackupMirrorStatus
        if directory == nil {
            status = await backupMirror.configure(at: nil, snapshots: [:])
        } else {
            let snapshots = Dictionary(uniqueKeysWithValues: BackupKind.allCases.map {
                ($0, backupDirs($0))
            })
            status = await backupMirror.configure(at: directory, snapshots: snapshots)
        }
        guard backupMirrorReconfigurationGeneration == generation else { return status }

        backupMirrorReconfigurationGeneration = nil
        let deferred = deferredBackupMirrorJobs
        deferredBackupMirrorJobs.removeAll()
        if status.directory != nil, status.errorDescription == nil {
            for (kind, source) in deferred {
                enqueueBackupMirror(kind, source: source)
            }
        }
        return status
    }

    func backupMirrorStatus() async -> BackupMirrorStatus {
        await backupMirror.status()
    }

    func waitForBackupMirror() async {
        let pending = Array(pendingBackupMirrorTasks.values)
        for task in pending {
            await task.value
        }
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

    private func enqueueBackupMirror(_ kind: BackupKind, source: URL) {
        guard !backupMirrorReconfigurationInProgress else {
            deferredBackupMirrorJobs.append((kind, source))
            return
        }
        let id = UUID()
        let mirror = backupMirror
        pendingBackupMirrorTasks[id] = Task { [weak self] in
            await mirror.mirror(kind, source: source)
            await self?.finishBackupMirrorTask(id)
        }
    }

    private func finishBackupMirrorTask(_ id: UUID) {
        pendingBackupMirrorTasks[id] = nil
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
