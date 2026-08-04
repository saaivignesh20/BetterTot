# BetterTot Specification

## Status

BetterTot is a private/local native macOS menu-bar scratchpad. The
current implementation provides seven fixed plain-text pads, a custom
nonactivating AppKit panel, local-first file storage, crash recovery, rolling
backups, import/export, settings, and a configurable global shortcut.

This document describes the repository as implemented, not a future product
roadmap.

## Product Goals

- Provide a fast, always-available scratchpad from the macOS menu bar.
- Keep all user note data local, plain-text, and readable outside the app.
- Preserve acknowledged edits through crashes, process kills, and metadata
  corruption whenever the filesystem permits it.
- Avoid accounts, background network services, analytics, telemetry, and
  proprietary data formats.
- Support predictable keyboard-first use across seven fixed pad slots.

## Non-Goals

- BetterTot is not a rich-text editor. Pads are stored and edited as plain text.
- BetterTot is not a syncing app. There is no cloud transport or remote state.
- BetterTot is not an encrypted vault. Stored files rely on the user's normal
  macOS account, permissions, FileVault, and backup configuration.
- BetterTot is not a document-based macOS app. It runs as an accessory
  menu-bar application.

## Platform and Packaging

- Language: Swift.
- Build system: Swift Package Manager.
- Minimum platform: macOS 13.
- Package targets:
  - `BetterTot`: executable target.
  - `BetterTotTests`: XCTest test target.
- Third-party dependencies: none.
- Apple frameworks used by the implementation include AppKit, Carbon,
  ServiceManagement, and UniformTypeIdentifiers.

Primary commands:

```sh
swift run
swift test
scripts/bundle.sh
scripts/test.sh
scripts/release.sh
```

`scripts/bundle.sh` builds a universal arm64/x86_64 release binary, creates
`dist/BetterTot.app`, writes a versioned `Info.plist`, sets `LSUIElement` for
menu-bar behavior, and signs the bundle. Its default ad-hoc signature is for
local use; a Developer ID identity enables Hardened Runtime and timestamped
signing. Launch-at-login support is only enabled when BetterTot is running from
an app bundle.

`scripts/release.sh` runs the tests and creates a versioned ZIP, unsigned macOS
installer package, and shared SHA-256 checksum. The app inside both artifacts
is ad-hoc signed. This is the completed path for the current private/local
scope. A matching version tag runs the same build in CI and stores it as a
repository-scoped Actions artifact. The tag workflow does not use Apple
credentials, notarize the app or installer, create a GitHub Release, or publish
a Homebrew Cask.

## Repository Layout

```text
Package.swift                         SwiftPM package manifest
README.md                             Project overview and quick start
CONTRIBUTION.md                       Development and contribution workflow
SECURITY.md                           Vulnerability reporting policy
SPEC.md                               This implementation specification
PLAN.md                               Original product and engineering plan
VERSION                               Release marketing version
Assets/MenuBarIcon.png                Material note-stack status-item artwork
docs/MANUAL_TESTING.md                Manual app acceptance checklist
docs/PRIVACY.md                       Privacy and local-storage notes
docs/RELEASE.md                       Local and tagged-build release runbook
scripts/bundle.sh                     Universal app bundle builder
scripts/package-installer.sh          Unsigned /Applications installer builder
scripts/release.sh                    ZIP, installer, checksum, and verification
scripts/verify-release.sh             Artifact integrity and signature checks
.github/workflows/*.yml               CI and read-only tagged-build automation
Sources/BetterTot/App.swift           App entry point
Sources/BetterTot/AppDelegate.swift   Launch, status item, menu, termination
Sources/BetterTot/PanelController.swift
                                      Panel behavior, editor, pad switching
Sources/BetterTot/CheckboxTextView.swift
                                      Markdown projection, native checkbox
                                      attachments, and coordinate mapping
Sources/BetterTot/PanelView.swift     Panel controls, layout, and status footer
Sources/BetterTot/Model.swift         Codable data model
Sources/BetterTot/WorkspaceStore.swift
                                      Actor-isolated persistence and recovery
Sources/BetterTot/Backups.swift       Backup, export-all, pruning logic
Sources/BetterTot/ImportExport.swift  Menu-driven import/export/restore
Sources/BetterTot/Shortcuts.swift     Shortcut model and Carbon hotkeys
Sources/BetterTot/SettingsWindow.swift
                                      Settings UI and UserDefaults bindings
Sources/BetterTot/SettingsContentView.swift
                                      Vertical navigation and settings page layout
Sources/BetterTot/MenuBarIcon.swift    Template status-item icon
Sources/BetterTot/UpdateChecker.swift Version parsing and manual release check
Tests/BetterTotTests/*.swift          XCTest coverage
```

## Application Lifecycle

1. `BetterTotApp.main()` creates `NSApplication.shared`, installs
   `AppDelegate`, sets the activation policy to `.accessory`, and runs the app.
2. `AppDelegate.applicationDidFinishLaunching` registers default preferences,
   installs a minimal main menu, creates a `WorkspaceStore`, and loads storage.
3. The app intentionally remains invisible until `WorkspaceStore.load()`
   finishes directory setup, metadata repair, and journal recovery.
4. After load, the app creates the menu-bar status item, `PanelController`,
   status menu, and `CarbonGlobalShortcutService`.
5. On termination, `applicationShouldTerminate` waits for `PanelController` to
   flush all pad text and asks `WorkspaceStore` to mark a clean shutdown before
   allowing the app to quit.

## User Interface

### Menu-Bar Item

- Left-click toggles the scratchpad panel.
- Right-click or Control-left-click opens the status menu.
- The status item uses a custom monochrome template icon based on BetterTot's
  stacked-note mark, with an accessibility description of "BetterTot
  scratchpad".

Status menu actions:

- Settings
- Create Backup Now
- Open Backup Folder
- Restore Backup
- Import Into Current Pad
- Export Current Pad
- Export All Pads
- Quit BetterTot

### Scratchpad Panel

The editor is a borderless, floating, nonactivating `NSPanel` containing:

- A compact header with Close, seven independent colored pad buttons, Pin, and
  Settings. Pin is immediately beside Settings.
- A scrollable plain-text `NSTextView`.
- A status footer with text statistics and local-save state.
- A flat semantic background clipped to a continuous rounded silhouette.

Panel behavior:

- The panel is anchored under the status item and clamped to the visible screen.
- The panel can become key even though the app is accessory-only.
- The editor receives focus whenever the panel opens.
- The unpinned panel dismisses on Escape or outside click.
- Dragging the attached panel background away from its menu-bar position pins
  it automatically and updates the Pin control.
- The Pin control also toggles the attached/pinned state directly.
- The pinned panel does not dismiss on outside click.
- Toggling while pinned brings the panel/key focus forward instead of hiding it.
- Explicitly closing a pinned panel clears its pinned state, so the next open
  returns beneath the menu-bar item.
- Opening Settings from an attached panel dismisses the popover first.
- A compact header contains Close, seven colored scratchpad selectors, Pin,
  and Settings. Inactive selectors are rings and the active selector is filled.
- A footer shows live line, word, and character counts together with the
  current local-save state (`Saving`, `Saved`, recovery pending, or failure).
- The panel uses semantic colors so its flat appearance follows the active
  macOS light or dark appearance without showing the desktop through it.
- Clicking the status item is excluded from outside-click handling so one click
  closes an open, unpinned panel without dismissing and reopening it.
- Clicking AppKit auxiliary panels such as spelling and correction suggestions
  does not dismiss the scratchpad.
- Escape is ignored by BetterTot while the text view has marked text, allowing
  input methods to handle IME composition cancellation.
- AppKit Writing Tools are disabled for the scratchpad editor, preventing the
  macOS 27 Write with Siri cursor accessory from covering compact pad content.
- Return continues plain `- ` lines without changing their marker.
- Typing `* ` starts bullet mode: the editor renders `• ` while persistence,
  copying, and export retain the portable Markdown `* ` marker.
- Footer controls toggle bulleted, numbered, or checkbox formatting across the
  current line or selected lines. Numbered lists increment on Return.
- Checkboxes are persisted and exported as Markdown task-list markers:
  `- [ ] ` and `- [x] `. The editor projects those markers into native inline
  TextKit attachment cells tinted to match the selected pad.
- The source/display adapter maps UTF-16 selections between Markdown source
  coordinates and attachment-backed editor coordinates. Attachments never leak
  object-replacement characters into journals, backups, exports, or pasteboard
  text.
- Clicking an attachment or pressing Command-Return on its line toggles state
  through the normal undo and persistence pipeline.
- Return continues rendered checkboxes and legacy `☐`, `☑`, `- [ ] `, `- [x] `,
  or `- [X] ` input with a new unchecked task. Legacy forms normalize to
  Markdown when persisted without rewriting unrelated text.
- Return on an empty dash, bullet, numbered item, or checkbox removes the marker
  and exits the list.
- Checklist paragraphs use a font-scaled hanging indent so wrapped lines align
  with their text rather than the checkbox gutter.
- Automatic list handling is disabled while the text view has marked text, so
  Return remains available to the active input method.

### Pad Slots

- There are exactly seven logical pads.
- Pads are addressed by fixed positions `0...6` internally. The panel displays
  colored dots; numeric identities remain in tooltips, accessibility labels,
  keyboard shortcuts, announcements, and exported file names.
- Each pad has an independent text buffer, selection, scroll offset, content
  revision, and undo manager.
- Pad switches persist the outgoing pad's selection/scroll state, commit any
  pending text save, load the incoming pad, and announce the selected pad to
  VoiceOver.
- The model includes optional `name` and `colorIdentifier` fields. Recognized
  color identifiers override the deterministic seven-color fallback palette.

## Keyboard Behavior

Global shortcut:

- Default: Option-Command-Space.
- Configurable in Settings.
- Implemented through Carbon event hotkeys.
- Persisted shortcuts are revalidated when loaded from `UserDefaults`.
- A valid shortcut must use Command, Option, or Control unless the key is an
  F-key.

Panel/editor shortcuts:

| Shortcut | Behavior |
| --- | --- |
| `Command-1` ... `Command-7` | Select pad 1 ... 7 |
| `Command-Left` | Previous pad |
| `Command-Right` | Next pad |
| `Shift-Command-C` | Copy entire current pad |
| `Shift-Command-Delete` | Clear current pad through undoable text editing |
| `Command-P` | Pin or unpin panel |
| `Command-W` | Close an attached or pinned panel |
| `Command-Return` | Toggle the checkbox on the current line |
| `Return` | Continue a bullet or checkbox; exit an empty list item |
| `Escape` | Dismiss unpinned panel unless IME composition is active |
| `Command-Q` | Quit BetterTot |
| `Command-,` | Open Settings |
| `Command-Z` / `Shift-Command-Z` | Undo / redo |
| `Command-X/C/V/A` | Standard cut, copy, paste, select all |

Bare `Command-Left` and `Command-Right` intentionally switch pads, which
shadows the normal line-start and line-end caret navigation in the editor.

## Settings

Settings are stored in standard app `UserDefaults`.

The settings window uses a fixed-size vertical sidebar with four pages:
`General`, `Editor`, `Storage`, and `Updates`. Each page icon sits in a circular
material container. The selected icon uses the system accent color while
inactive icons remain gray; the row itself stays transparent. Switching pages
does not resize the window or interrupt the scratchpad panel.

Supported settings:

- Launch at login, via `SMAppService.mainApp`, enabled only in a bundled app.
- Global shortcut.
- Check spelling while typing.
- Smart quotes.
- Smart dashes.
- Editor font name and size.

The settings window also displays backup counts for hourly, daily, and manual
backup tiers and provides a button to open the backup folder.

The Updates page displays the installed version/build and performs a check only
after the user presses `Check for Updates`. It requests the latest public
GitHub release through an ephemeral `URLSession`, validates semantic versions,
response size, and the HTTPS GitHub release URL, and never downloads or
installs software. Overlapping checks are rejected.

Shortcut recording behavior:

- Clicking the shortcut button starts a local key-down monitor.
- Recording only captures events aimed at the settings window.
- Bare Escape cancels recording.
- Invalid shortcuts beep and keep recording active.
- If Carbon registration fails, the previous shortcut is restored and the user
  receives an actionable alert.
- Recording ends when the settings window resigns key or closes.

## Data Model

### `PadID`

`PadID` wraps a UUID and is used as the stable identity for pad files and
metadata records.

### `StoredSelection`

Selection is stored as UTF-16 location and length because `NSTextView` uses
`NSRange`. Selections are clamped against the current text length before being
restored.

### `PadMetadata`

Each pad metadata record contains:

- `id`
- `position`
- `name`
- `colorIdentifier`
- `selection`
- `scrollOffset`
- `contentRevision`
- `updatedAt`

### `WorkspaceMetadata`

Workspace metadata contains:

- `schemaVersion`
- `selectedPadID`
- `pads`
- `lastCleanShutdown`

Current schema version: `1`.

Workspace invariants:

- Exactly seven pad metadata records.
- Unique pad IDs.
- Positions normalized to `0...6`.
- Selected pad ID must refer to an existing pad.
- Metadata repair may drop extra metadata records but must not delete extra pad
  files from disk.

## Storage Layout

Default root:

```text
~/Library/Application Support/BetterTot/
```

Layout:

```text
BetterTot/
|-- Pads/
|   `-- <pad-uuid>.txt
|-- workspace.json
|-- workspace.json.corrupt
|-- Journal/
|   |-- <pad-uuid>.log
|   `-- recovered/
|       |-- <pad-uuid>-<timestamp>.txt
|       `-- <pad-uuid>-<timestamp>.corrupt
`-- Backups/
    |-- hourly/
    |   `-- <yyyyMMdd-HHmmss>/
    |-- daily/
    |   `-- <yyyyMMdd-HHmmss>/
    `-- manual/
        `-- <yyyyMMdd-HHmmss>/
```

Pad text files:

- One UTF-8 text file per pad.
- File name is the pad UUID plus `.txt`.
- Empty pads may have missing files or zero-byte files depending on the save
  history.

Metadata:

- `workspace.json` stores pad order, selected pad, per-pad UI state, revisions,
  and clean-shutdown marker.
- `workspace.json` does not store note text.
- Corrupt or incompatible metadata is preserved as `workspace.json.corrupt` and
  rebuilt by adopting existing pad files.

## Persistence and Recovery

`WorkspaceStore` is an actor and is the single writer for pad files, journals,
metadata, backups, and export-all operations.

### Load

On load, the store:

1. Creates `root`, `Pads`, `Journal`, and `Journal/recovered` directories.
2. Migrates a legacy root-level `pad.txt` into a UUID-named pad file when no
   metadata exists.
3. Loads `workspace.json` or rebuilds metadata from existing pad files.
4. Repairs workspace invariants.
5. Reads each pad file as UTF-8 text.
6. Preserves unreadable pad bytes to `Journal/recovered/*.corrupt` and opens
   that pad as empty.
7. Replays the newest valid journal entry for each pad if its revision is newer
   than the committed revision.
8. Clears stale or successfully recovered journals.
9. Marks the live session as not cleanly shut down and writes metadata.

Journal recovery rules:

- Journal files are JSON Lines.
- Each journal entry is a full-text snapshot, not a diff.
- The newest valid entry by revision wins.
- Torn or undecodable trailing lines are ignored without poisoning earlier
  valid lines.
- Recovery preserves the previous committed file in `Journal/recovered/` when
  it differs from the journaled text.
- If recovery cannot write the pad file, the journal is retained and the UI
  revision seed is set so a later successful commit retries the recovery.
- Metadata must never claim a revision that the pad file does not contain.

### Edit and Commit

On every `NSTextView` change:

1. The selected pad's in-memory text is updated.
2. The pad revision is incremented.
3. A full-text journal entry is appended.
4. A 200 ms debounced commit is scheduled.

On commit:

1. Stale revisions are ignored.
2. The pad text is written atomically as UTF-8.
3. The pad's `contentRevision` and `updatedAt` are updated.
4. The journal is cleared when the committed revision is at least the newest
   journaled revision.
5. Metadata is atomically written.
6. Hourly/daily auto-backup checks run after successful commits.

On pad switch, dismiss, and quit, pending commits are flushed synchronously from
the controller's perspective.

## Backups

Backup kinds:

| Kind | Retention |
| --- | --- |
| `hourly` | Newest 24 timestamped backup directories |
| `daily` | Newest 14 timestamped backup directories |
| `manual` | Unlimited; kept until the user deletes them |

Backup directory names use UTC timestamps in `yyyyMMdd-HHmmss` format. Same
second collisions are uniquified with suffixes such as `-1`.

Each backup contains:

```text
Pad 1.txt
Pad 2.txt
Pad 3.txt
Pad 4.txt
Pad 5.txt
Pad 6.txt
Pad 7.txt
workspace.json
```

Backup rules:

- Backups copy pad files by pad position.
- Missing source pad files produce empty backup files.
- Only timestamp-named directories are counted, aged, or pruned.
- User-created or renamed folders inside backup tiers are ignored and not
  deleted by pruning.
- Auto-backups are write-driven rather than timer-driven.
- Hourly and daily backups are created when the newest backup in that tier is
  older than one hour or one day respectively.

## Import, Export, and Restore

Import current pad:

- Accepts a single text file through `NSOpenPanel`.
- Reads only regular, non-symlink UTF-8 or BOM-marked UTF-16 files up to
  16 MiB; other inputs are rejected without reading them into the editor.
- Empty current pad is replaced directly.
- Non-empty current pad prompts for Replace, Append, or Cancel.
- Replace first commits all edited pads and creates a manual safety backup.
- If the safety backup fails, import is cancelled and the pad is unchanged.
- Append inserts a newline first when the existing pad does not end in one.
- Imports route through normal text editing so they are undoable and journaled.

Export current pad:

- Uses `NSSavePanel`.
- Default file name: `Pad N.txt`.
- Writes the current editor string as UTF-8 plain text.

Export all pads:

- Uses a directory picker.
- Commits all edited pads before export.
- Writes `Pad 1.txt` through `Pad 7.txt`.
- Copies workspace metadata as `metadata.json` when available.

Restore backup:

- Uses a directory picker rooted at the backup folder.
- Expects one or more `Pad N.txt` files.
- Refuses folders with no `Pad N.txt` files.
- Commits all edited pads and creates a manual safety backup before restoring.
- If the safety backup fails, restore is cancelled and current data remains.
- Restores by position, not by UUID.
- Missing files are skipped silently.
- Existing unreadable files are reported and leave their pads unchanged.
- Restored text is committed before success is reported.
- Undo stacks are cleared after restore.
- Restore does not consume the backup's `workspace.json`.

## Privacy and Security

Privacy posture:

- No background or automatic network requests.
- A user-initiated update check requests public release metadata from
  `api.github.com`; no note or workspace data is included.
- No analytics, telemetry, advertising SDKs, or accounts.
- No collection of note content, clipboard content, or file content.
- Data is stored locally in plain files.

Logging policy:

- Logs may include operational failures such as save, backup, shortcut, or login
  item errors.
- Logs must not include note content, clipboard content, imported text, exported
  text, or full file contents.

Security limitations:

- BetterTot does not encrypt pad files, journals, recovered files, backups, or
  exported files.
- Deleted pad text can remain in journals, recovered files, backups, external
  exports, Time Machine, or other system backups.
- "Clear pad" clears the active pad text, not historical backup or recovery
  material.

## Accessibility and International Text

Implemented accessibility support:

- Status item image has an accessibility description.
- Segment control is labelled "Scratchpads".
- Each segment has a `Scratchpad N` tooltip.
- The text view accessibility label updates to the selected scratchpad.
- Pad switches post VoiceOver announcements, including an "empty" suffix when
  applicable.

International text behavior:

- Pad files are strict UTF-8 on normal writes.
- Text and selection handling accounts for UTF-16 `NSTextView` ranges.
- Escape does not dismiss the panel while IME marked text is active.
- Tests cover Unicode text persistence and UTF-16 selection clamping.

## Testing Baseline

Automated test command:

```sh
swift test
```

Current automated coverage is concentrated in:

- `WorkspaceStoreTests`: workspace invariants, metadata repair, commit/reload,
  journal recovery, stale revision handling, corrupted metadata containment,
  orphan adoption, torn journal handling, unreadable pad preservation, empty
  commit durability, legacy migration, clean-shutdown marker, and selection
  clamping.
- `BackupTests`: manual backups, hourly/daily pruning, manual retention,
  same-second backup collisions, stray backup folders, commit-triggered
  auto-backups, and export-all layout.
- `RestoreTests`: restore-by-position behavior, missing file skips, and
  unreadable existing file reporting.
- `ShortcutTests`: shortcut validation, display formatting, Codable round trips,
  Carbon registration lifecycle, failed re-registration behavior, persisted
  shortcut validation, and event-to-shortcut conversion.
- `PanelControllerTests`: ordinary Return behavior, automatic bullet and
  checkbox continuation, attachment and keyboard checkbox toggling, Markdown
  serialization, empty-item list exit, IME command ownership, panel dismissal,
  pinning, focus, pad switching, and undo isolation.

Manual checklist coverage remains important for UI behaviors that are hard to
exercise through the current test suite:

- Editor focus from status item and global shortcut.
- Return inserting ordinary newlines, continuing lists, and exiting empty list
  items without dismissing.
- Outside-click dismissal when unpinned.
- Pin/unpin preserving editor and undo history.
- Rapid pad switching while typing.
- Undo isolation across pads.
- Selection and scroll restoration in the visible UI.
- Multi-display panel positioning.
- IME composition behavior.
- Settings shortcut recording interactions.
- VoiceOver reachability and announcements.
- Launch-at-login behavior from the bundled app.

Verification performed while writing this spec:

```text
swift test
Executed 117 tests, with 0 failures.
Line coverage: 87.21% (2768/3174), minimum 80.00%.
```

## Current Gaps and Risks

- `scripts/test.sh` enforces at least 80% aggregate source line coverage and a
  30% floor for every non-entry source file. The current instrumented result is
  87.21% across 117 passing tests.
- VoiceOver, IME, multi-display positioning, and launch-at-login remain manual
  acceptance checks. The local checklist passed on 2026-07-27 and must be
  repeated for a future public-distribution candidate if scope changes.
- Launch-at-login can only be exercised meaningfully from `dist/BetterTot.app`.
- `name` and `colorIdentifier` fields are persisted model fields without active
  UI affordances.
- Backups and recovered journals intentionally preserve user text beyond active
  pad deletion; an explicit "erase history" action does not exist.
- Notarization and clean-Mac Gatekeeper acceptance are intentionally outside
  the current private/local distribution scope.
- The layered seven-pad application icon is generated deterministically from
  `Assets/AppIcon.svg` and embedded in release bundles as `BetterTot.icns`.

## Contribution Constraints

- Preserve the local-first privacy model unless a future product decision
  explicitly changes it.
- Never log note text, clipboard text, imported file contents, exported file
  contents, or recovered file contents.
- Keep the seven-pad invariant unless both storage and UI specs are updated.
- Treat `WorkspaceStore` as the single disk writer for workspace data.
- Preserve crash recovery semantics when changing editor, journal, or commit
  behavior.
- Any destructive import or restore path must keep the existing safety-backup
  behavior or replace it with a stronger recovery guarantee.
- Changes to keyboard handling must account for the nonactivating panel and
  should not break standard editing commands.
- Changes to selection handling must respect UTF-16 `NSTextView` ranges.
- New storage schema versions need deterministic repair or migration behavior
  that never deletes existing pad text files as a side effect.
