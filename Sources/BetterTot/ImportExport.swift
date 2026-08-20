import AppKit
import Darwin
import UniformTypeIdentifiers

enum ImportChoice {
    case replace
    case append
    case cancel
}

enum ImportResult: Equatable {
    case imported
    case cancelled
    case backupFailed
}

enum RestoreBackupResult: Equatable {
    case noPadFiles
    case safetyBackupFailed
    case persistenceFailed
    case restored(skipped: [Int])
}

// Menu-driven import/export/backup actions (plan §10). File dialogs run
// modally; the unpinned panel may already have been dismissed by the click
// that opened the menu, so successful actions call show() to present results.
extension PanelController {
    static let maximumImportedTextBytes = 16 * 1024 * 1024

    @objc func importIntoCurrentPad(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .text]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let imported = Self.readTextFile(url) else {
            presentError("Could not read “\(url.lastPathComponent)” as text.")
            return
        }

        let choice: ImportChoice
        if currentSourceText.isEmpty {
            choice = .replace
        } else {
            let alert = NSAlert()
            alert.messageText = "Import into a non-empty pad?"
            alert.informativeText = "Replace makes a backup of all pads first."
            alert.addButton(withTitle: "Replace")
            alert.addButton(withTitle: "Append")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                choice = .replace
            case .alertSecondButtonReturn:
                choice = .append
            default:
                return
            }
        }
        Task { @MainActor in
            switch await importText(imported, choice: choice) {
            case .imported:
                show()
            case .backupFailed:
                presentError("Backup failed — import cancelled. Nothing was changed.")
            case .cancelled:
                break
            }
        }
    }

    @objc func exportCurrentPad(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Pad \(currentPadPosition + 1).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try writeCurrentPad(to: url)
        } catch {
            presentError("Export failed: \(error.localizedDescription)")
        }
    }

    @objc func exportAllPads(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        Task { @MainActor in
            do {
                try await writeAllPads(to: directory)
            } catch {
                presentError("Export failed: \(error.localizedDescription)")
            }
        }
    }

    @objc func createManualBackup(_ sender: Any?) {
        Task { @MainActor in
            let created = await makeManualBackup()
            if !created {
                presentError("Backup failed — check the log for details.")
            }
        }
    }

    @objc func openBackupFolder(_ sender: Any?) {
        NSWorkspace.shared.open(store.backupsDirectory)
    }

    @objc func restoreBackup(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = store.backupsDirectory
        panel.message = "Choose a backup folder (contains Pad 1.txt … Pad \(WorkspaceMetadata.padCount).txt)"
        panel.prompt = "Restore"
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        Task { @MainActor in
            switch await restoreWorkspace(from: directory) {
            case .noPadFiles:
                presentError("That folder contains no “Pad N.txt” files.")
            case .safetyBackupFailed:
                presentError("Safety backup failed — restore cancelled. Nothing was changed.")
            case .persistenceFailed:
                presentError("Restore could not be saved. Recovery data and the safety backup were kept.")
            case .restored(let skipped):
                if !skipped.isEmpty {
                    presentError("Restored, but could not read: "
                        + skipped.map { "Pad \($0 + 1).txt" }.joined(separator: ", ")
                        + ". Those pads keep their current content.")
                }
                show()
            }
        }
    }

    // MARK: - Non-dialog workflows

    func importText(_ imported: String, choice: ImportChoice) async -> ImportResult {
        if currentSourceText.isEmpty {
            applyToCurrentPad(imported, replacing: true)
            return .imported
        }
        switch choice {
        case .append:
            applyToCurrentPad(imported, replacing: false)
            return .imported
        case .cancel:
            return .cancelled
        case .replace:
            let confirmedPad = currentPadPosition
            let backedUp = await withEditingSuspended {
                await createBackupIncludingCurrentPad()
            }
            guard backedUp else { return .backupFailed }
            selectPad(at: confirmedPad)
            applyToCurrentPad(imported, replacing: true)
            return .imported
        }
    }

    func writeCurrentPad(to url: URL) throws {
        try currentSourceText.write(to: url, atomically: true, encoding: .utf8)
    }

    func writeAllPads(to directory: URL) async throws {
        try await withEditingSuspended {
            guard await commitAllPadsAndWait() else {
                throw CocoaError(.fileWriteUnknown)
            }
            try await store.exportAllPads(to: directory)
        }
    }

    func makeManualBackup() async -> Bool {
        await withEditingSuspended { await createBackupIncludingCurrentPad() }
    }

    func createSettingsBackup() async -> Bool {
        await makeManualBackup()
    }

    func restoreBackupFromSettings() {
        restoreBackup(nil)
    }

    func restoreWorkspace(from directory: URL) async -> RestoreBackupResult {
        let padFiles = (1...WorkspaceMetadata.padCount).map {
            directory.appendingPathComponent("Pad \($0).txt")
        }
        guard padFiles.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            return .noPadFiles
        }
        return await withEditingSuspended {
            guard await createBackupIncludingCurrentPad() else { return .safetyBackupFailed }
            guard let skipped = await restore(from: padFiles) else { return .persistenceFailed }
            return .restored(skipped: skipped)
        }
    }

    private func createBackupIncludingCurrentPad() async -> Bool {
        guard await commitAllPadsAndWait() else { return false }
        return await store.createBackup(.manual) != nil
    }

    static func readTextFile(_ url: URL) -> String? {
        let descriptor = open(url.path, O_RDONLY | O_NONBLOCK | O_NOFOLLOW)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }

        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_size >= 0,
              info.st_size <= maximumImportedTextBytes,
              let data = try? handle.read(upToCount: maximumImportedTextBytes + 1),
              data.count <= maximumImportedTextBytes else {
            return nil
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        let hasUTF16ByteOrderMark = data.starts(with: [0xFF, 0xFE])
            || data.starts(with: [0xFE, 0xFF])
        guard hasUTF16ByteOrderMark, data.count.isMultiple(of: 2) else { return nil }
        return String(data: data, encoding: .utf16)
    }

    private func presentError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.runModal()
    }
}
