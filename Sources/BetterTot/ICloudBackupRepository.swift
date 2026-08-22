import Foundation

struct BackupRepositoryLocation: Equatable, Sendable {
    let directory: URL
    let unavailableReason: String?

    var isAvailable: Bool { unavailableReason == nil }

    static func available(_ directory: URL) -> Self {
        Self(directory: directory.standardizedFileURL, unavailableReason: nil)
    }

    static func unavailable(_ directory: URL, reason: String) -> Self {
        Self(directory: directory.standardizedFileURL, unavailableReason: reason)
    }
}

protocol ICloudBackupLocationResolving: Sendable {
    func resolve() -> BackupRepositoryLocation
}

struct PrivateICloudDriveBackupLocationResolver: ICloudBackupLocationResolving {
    static let repositoryFolderName = "BetterTot Backups (org.bettertot.BetterTot)"

    private let cloudDriveRoot: URL

    init(
        cloudDriveRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    ) {
        self.cloudDriveRoot = cloudDriveRoot.standardizedFileURL
    }

    func resolve() -> BackupRepositoryLocation {
        let repository = cloudDriveRoot.appendingPathComponent(
            Self.repositoryFolderName,
            isDirectory: true
        )
        guard cloudDriveRoot.isFileURL, cloudDriveRoot.path != "/" else {
            return .unavailable(repository, reason: "The iCloud Drive location is invalid.")
        }

        do {
            let values = try cloudDriveRoot.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                return .unavailable(repository, reason: "iCloud Drive is unavailable.")
            }
            guard FileManager.default.isWritableFile(atPath: cloudDriveRoot.path) else {
                return .unavailable(repository, reason: "iCloud Drive is not writable.")
            }
            return .available(repository)
        } catch {
            return .unavailable(repository, reason: "Sign in to iCloud Drive to enable backups.")
        }
    }
}

enum BackupRepositoryHealth: Equatable, Sendable {
    case ready
    case unavailable(String)
    case blocked(String)
}

struct BackupRepositorySummary: Equatable, Sendable {
    let health: BackupRepositoryHealth
    let directory: URL
    let canOpenDirectory: Bool
    let latestBackupDate: Date?
    let latestBackupSizeBytes: Int64?
    let counts: [BackupKind: Int]

    var totalCount: Int { counts.values.reduce(0, +) }
}

struct BackupRepositoryManifest: Codable, Equatable, Sendable {
    static let fileName = "repository.json"
    static let current = Self(
        format: "org.bettertot.backup-repository",
        schemaVersion: 1,
        bundleIdentifier: "org.bettertot.BetterTot",
        repositoryIdentifier: "org.bettertot.BetterTot.backups"
    )

    let format: String
    let schemaVersion: Int
    let bundleIdentifier: String
    let repositoryIdentifier: String
}

struct LegacyBackupMigrationRecord: Codable, Equatable, Sendable {
    static let fileName = "legacy-migration-v1.json"

    let schemaVersion: Int
    let completedAt: Date
}

enum BackupRepositoryValidation {
    private static let systemMetadataNames: Set<String> = [".DS_Store", ".localized"]

    static func prepare(
        _ location: BackupRepositoryLocation,
        fileManager: FileManager = .default
    ) -> BackupRepositoryHealth {
        if let reason = location.unavailableReason {
            return .unavailable(reason)
        }

        let directory = location.directory
        let parent = directory.deletingLastPathComponent()
        guard isPlainDirectory(parent, fileManager: fileManager) else {
            return .unavailable("iCloud Drive is unavailable.")
        }

        if fileManager.fileExists(atPath: directory.path) {
            guard isPlainDirectory(directory, fileManager: fileManager) else {
                return .blocked("The BetterTot iCloud backup path is not a regular folder.")
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: false
                )
            } catch {
                return .unavailable("BetterTot could not create its iCloud backup folder.")
            }
        }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            return .unavailable("BetterTot could not read its iCloud backup folder.")
        }

        let allowed = Set(BackupKind.allCases.map(\.rawValue) + [
            BackupRepositoryManifest.fileName,
            LegacyBackupMigrationRecord.fileName,
        ]).union(systemMetadataNames)
        let unknown = contents.filter { !allowed.contains($0.lastPathComponent) }
        guard unknown.isEmpty else {
            return .blocked("This folder contains files that do not belong to BetterTot.")
        }
        for child in contents where BackupKind(rawValue: child.lastPathComponent) != nil {
            guard isPlainDirectory(child, fileManager: fileManager) else {
                return .blocked("The BetterTot backup hierarchy is malformed.")
            }
            if let problem = validateTier(child, fileManager: fileManager) {
                return .blocked(problem)
            }
        }

        let manifestURL = directory.appendingPathComponent(BackupRepositoryManifest.fileName)
        if fileManager.fileExists(atPath: manifestURL.path) {
            guard let values = try? manifestURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(
                    BackupRepositoryManifest.self,
                    from: data
                  ),
                  manifest == .current else {
                return .blocked("The iCloud backup folder belongs to another or newer repository.")
            }
        } else {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(BackupRepositoryManifest.current).write(
                    to: manifestURL,
                    options: .atomic
                )
            } catch {
                return .unavailable("BetterTot could not initialize its iCloud backup folder.")
            }
        }

        let migrationURL = directory.appendingPathComponent(LegacyBackupMigrationRecord.fileName)
        if fileManager.fileExists(atPath: migrationURL.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let values = try? migrationURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let data = try? Data(contentsOf: migrationURL),
            let record = try? decoder.decode(LegacyBackupMigrationRecord.self, from: data),
            record.schemaVersion == 1 else {
                return .blocked("The BetterTot backup migration record is invalid.")
            }
        }
        return .ready
    }

    private static func isPlainDirectory(
        _ url: URL,
        fileManager: FileManager
    ) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
              ]) else {
            return false
        }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private static func validateTier(
        _ tier: URL,
        fileManager: FileManager
    ) -> String? {
        guard let snapshots = try? fileManager.contentsOfDirectory(
            at: tier,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return "BetterTot could not inspect its iCloud backup folder."
        }
        let allowedSnapshotFiles = Set(
            (1...WorkspaceMetadata.compatibleBackupPadCount).map { "Pad \($0).txt" }
                + ["workspace.json", ".bettertot-backup"]
        )
        for snapshot in snapshots {
            if systemMetadataNames.contains(snapshot.lastPathComponent) {
                continue
            }
            guard isSnapshotName(snapshot.lastPathComponent),
                  isPlainDirectory(snapshot, fileManager: fileManager),
                  let files = try? fileManager.contentsOfDirectory(
                    at: snapshot,
                    includingPropertiesForKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                    ],
                    options: []
                  ) else {
                return "The BetterTot backup hierarchy contains an invalid item."
            }
            for file in files {
                if systemMetadataNames.contains(file.lastPathComponent) {
                    continue
                }
                guard allowedSnapshotFiles.contains(file.lastPathComponent),
                      let values = try? file.resourceValues(forKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                      ]),
                      values.isRegularFile == true,
                      values.isSymbolicLink != true else {
                    return "A BetterTot backup contains an invalid file."
                }
            }
        }
        return nil
    }

    private static func isSnapshotName(_ name: String) -> Bool {
        guard name.count >= 15 else { return false }
        let prefix = String(name.prefix(15))
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.isLenient = false
        return formatter.date(from: prefix) != nil
    }
}
