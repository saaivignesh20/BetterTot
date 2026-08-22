# BetterTot — Corrected Product and Engineering Plan

## 1. Product definition

### Working description

BetterTot is a native, open-source macOS menu-bar scratchpad.

It provides a fixed collection of instantly accessible notes with:

* Immediate keyboard focus
* Automatic persistence
* Minimal interface
* Predictable keyboard behavior
* No folders, notebooks, accounts, or organizational overhead
* Local-first storage
* Optional synchronization in a later release

BetterTot is not intended to become a general-purpose note-taking or knowledge-management application.

### Core product promise

> Press one shortcut, type immediately, and never lose the text.

### Working name warning

“BetterTot” should remain a development codename until a trademark and naming review is completed.

Do not copy Tot’s:

* Name
* Icon
* Marketing copy
* Exact color palette
* Exact visual layout
* Screenshots or other assets

The product can implement the same general category and workflow while maintaining an independent design identity.

---

# 2. Product principles

Every feature should satisfy these principles.

## 2.1 Instant

The user should be able to:

1. Press the global shortcut.
2. Begin typing immediately.
3. Press Return without changing window state.
4. Dismiss the app without manually saving.

There should be no loading screen, note picker, sidebar, startup animation, or document-opening workflow.

## 2.2 Fixed, not organized

BetterTot should use eight permanent scratchpad slots.

Users do not:

* Create notebooks
* Delete note objects
* Move notes into folders
* Add tags
* Manage a note hierarchy

They may clear the contents of a slot, but the slot itself remains.

## 2.3 Local first

The application must work completely offline.

Version 0.1 should have:

* No account
* No analytics
* No advertising
* No telemetry
* No required network connection
* No cloud dependency

## 2.4 Native

Use native macOS technologies:

* Swift
* AppKit
* `NSPanel`
* `NSTextView`
* Swift Package Manager
* XCTest
* XCUITest

SwiftUI may be used selectively for settings and non-critical views, but the editor and window lifecycle should remain AppKit-controlled.

## 2.5 Deterministic

The panel should only close through explicitly defined actions.

Text-editing commands, focus changes, Return, paste, undo, input methods, and modifier combinations must not accidentally dismiss it.

---

# 3. Version 0.1 scope

## Required features

Version 0.1 should include:

1. Menu-bar-only application
2. Eight fixed scratchpads
3. Native plain-text editor
4. Custom menu-bar-attached panel
5. Configurable global keyboard shortcut
6. Keyboard switching between scratchpads
7. Automatic local persistence
8. Crash-recovery journal
9. Local rolling backups
10. Import and export
11. Light and dark appearance support
12. Configurable font and text size
13. Launch-at-login option
14. VoiceOver-compatible controls
15. Floating/pinned panel mode
16. Ad-hoc-signed private/local builds
17. Apple Silicon support
18. Automated regression testing
19. User-initiated update check

## Explicitly excluded from version 0.1

Do not include:

* iCloud synchronization
* iPhone or iPad applications
* Apple Watch support
* Rich text
* Rendered Markdown
* Markdown preview
* AI functionality
* Collaboration
* Accounts
* Folders
* Tags
* Plugins
* Browser extensions
* Clipboard management
* Git synchronization
* End-to-end encryption
* Automatic updates
* App Store distribution

These features would expand the project before its central interaction model is proven.

---

# 4. User experience

## 4.1 Menu-bar interaction

Clicking the menu-bar icon should:

1. Show the panel below the status item.
2. Display the last selected scratchpad.
3. Restore the previous selection and scroll position.
4. Make the editor the first responder.
5. Place the insertion point correctly.
6. Accept typing immediately.

Clicking the menu-bar icon again should dismiss the panel unless it is pinned.

## 4.2 Global shortcut interaction

The default shortcut can be:

```text
Option + Command + Space
```

It must be configurable.

Shortcut behavior:

* Hidden panel: show and focus
* Visible unpinned panel: dismiss
* Visible pinned panel: bring forward and focus
* Shortcut registration conflict: show an actionable error
* Invalid shortcut: reject it before saving

The shortcut implementation should be isolated behind an abstraction so the underlying registration mechanism can be replaced later.

```swift
protocol GlobalShortcutService {
    var currentShortcut: Shortcut? { get }

    func register(_ shortcut: Shortcut) throws
    func unregister()
}
```

Do not implement the feature by monitoring all keyboard input globally.

## 4.3 Scratchpad selection

Display eight slot indicators.

Each slot must have:

* A visible position
* A keyboard number
* An accessibility label
* An optional user-assigned color
* An optional short name

Color must not be the only way to distinguish slots.

Recommended shortcuts:

```text
Command + 1 ... Command + 8   Select slot
Control + Shift + Tab         Previous slot
Control + Tab                 Next slot
Command + Shift + C           Copy entire slot
Command + Shift + Delete      Clear slot
Escape                        Dismiss unpinned panel
```

Command + Left Arrow and Command + Right Arrow remain native text-navigation
commands and must not switch pads.

Clearing a non-empty pad should require confirmation or provide an immediately available undo action.

## 4.4 Return-key behavior

The following must insert text without affecting panel visibility:

```text
Return
Shift + Return
Option + Return
Command + Return
Control + Return
```

The editor should use the standard AppKit text system.

Do not override `insertNewline(_:)` unless BetterTot introduces a deliberate custom newline behavior. Calling `super.insertNewline(_:)` from an otherwise empty override provides no protection against panel dismissal.

## 4.5 Pinned mode

Users should be able to pin the panel.

Unpinned mode:

* Anchored below the menu-bar item
* Closes on outside click
* Closes on Escape
* Does not appear as a normal app window

Pinned mode:

* Becomes a movable floating panel
* Does not close on outside click
* Remains available across application changes
* Can be resized within sensible limits
* Maintains the same editor instance and state

Pinning must not recreate the editor or reload the note.

---

# 5. Window architecture

## 5.1 Use a custom `NSPanel`

Do not use `NSPopover` as the primary editor container.

Use:

```text
NSStatusItem
    └── ScratchpadPanelController
            └── ScratchpadPanel : NSPanel
                    └── EditorContainerView
                            └── NSScrollView
                                    └── NSTextView
```

`NSPanel` is intended for auxiliary windows, and a borderless window may need to explicitly allow key-window status. Apple documents that attempts to make a window key are abandoned when `canBecomeKey` is false. ([Apple Developer][1])

```swift
final class ScratchpadPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
```

## 5.2 Panel properties

Recommended starting configuration:

```swift
let panel = ScratchpadPanel(
    contentRect: initialFrame,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)

panel.isFloatingPanel = true
panel.hidesOnDeactivate = false
panel.isReleasedWhenClosed = false
panel.hasShadow = true
panel.level = .floating
panel.collectionBehavior = [
    .canJoinAllSpaces,
    .fullScreenAuxiliary
]
```

The exact style-mask configuration should be validated during the technical spike. A nonactivating panel and first-responder text input can interact in subtle ways, so acceptance tests—not assumptions—should determine the final configuration.

## 5.3 Explicit dismissal policy

Only the following code paths may dismiss an unpinned panel:

1. Escape command
2. Outside-click event
3. Status-item toggle
4. Global-shortcut toggle
5. Explicit Close command
6. Application termination

No other component should call:

```swift
orderOut(_:)
close()
performClose(_:)
```

The panel controller should own dismissal.

```swift
enum PanelDismissalReason {
    case escape
    case outsideClick
    case statusItemToggle
    case globalShortcutToggle
    case explicitClose
    case termination
}
```

Use one method:

```swift
func dismiss(reason: PanelDismissalReason)
```

This makes unintended dismissal paths searchable and testable.

## 5.4 Outside-click handling

Use scoped local and global mouse-event monitors only while an unpinned panel is visible.

Requirements:

* Monitor mouse events, not ordinary keyboard input.
* Remove monitors when the panel is hidden.
* Ignore clicks inside the panel.
* Ignore the opening click on the status item.
* Avoid retaining the controller strongly inside monitor closures.
* Never dismiss during an active drag or text selection within the panel.

## 5.5 Positioning

The panel should anchor to the status item’s screen rectangle.

The positioning logic must handle:

* Multiple displays
* Menu bar on a secondary display
* Notched displays
* Menu-bar auto-hide
* Display resolution changes
* Status-item movement
* Right-to-left interface direction
* Panel resizing
* Full-screen spaces

The panel should remain within the visible frame of the target screen.

---

# 6. Editor architecture

## 6.1 Use `NSTextView`

The core editor should be an `NSTextView` inside an `NSScrollView`.

Required behaviors:

* Standard undo and redo
* Standard text services
* Spell checking
* Smart substitutions as optional settings
* Input-method compatibility
* Emoji compatibility
* Selection restoration
* Scroll restoration
* Drag and drop
* Services menu support
* Accessibility support

Avoid SwiftUI `TextEditor` for the primary editing surface because BetterTot depends on precise responder-chain and selection control.

## 6.2 Editor controller

```swift
final class EditorController: NSViewController, NSTextViewDelegate {
    private let scrollView: NSScrollView
    private let textView: NSTextView
    private let workspaceStore: WorkspaceStore

    private var selectedPadID: PadID
    private var isLoadingPad = false
}
```

Responsibilities:

* Load selected-pad content
* Save text changes
* Restore selection
* Restore scroll position
* Preserve undo behavior
* Inform the workspace controller of changes
* Avoid triggering saves while programmatically loading a pad

## 6.3 Selection storage

`NSTextView` selections use `NSRange` and UTF-16 indexing semantics.

Store them explicitly:

```swift
struct StoredSelection: Codable, Equatable {
    var utf16Location: Int
    var utf16Length: Int
}
```

Before restoring:

```swift
let textLength = (text as NSString).length
let location = min(selection.utf16Location, textLength)
let remaining = textLength - location
let length = min(selection.utf16Length, remaining)

textView.setSelectedRange(
    NSRange(location: location, length: length)
)
```

Do not interpret the stored offsets as Swift `String.Index` positions.

## 6.4 Scroll position

Store either:

* The visible content origin, or
* The first visible character range

The value must be validated when restoring because text length and layout may have changed.

## 6.5 First-responder invariant

Whenever the panel is opened for editing:

```swift
panel.makeKeyAndOrderFront(nil)
panel.makeFirstResponder(textView)
```

The implementation must verify that:

```swift
panel.firstResponder === textView
```

or that the active field editor belongs to the text view.

Do not assume that showing the panel automatically focuses the editor.

---

# 7. Data model

## 7.1 Stable pad identifiers

Use stable identifiers independent of display order.

```swift
struct PadID: RawRepresentable, Codable, Hashable {
    let rawValue: UUID
}
```

## 7.2 Pad metadata

```swift
struct PadMetadata: Codable, Equatable {
    let id: PadID
    var position: Int
    var name: String?
    var colorIdentifier: String?
    var selection: StoredSelection
    var scrollOffset: Double
    var contentRevision: UInt64
    var updatedAt: Date
}
```

The text itself should not be stored in this structure.

## 7.3 Workspace metadata

```swift
struct WorkspaceMetadata: Codable {
    var schemaVersion: Int
    var selectedPadID: PadID
    var pads: [PadMetadata]
    var windowState: WindowState
    var lastCleanShutdown: Bool
}
```

## 7.4 Fixed-slot invariant

The store should ensure:

* Exactly eight active pads
* Unique IDs
* Unique positions from zero through seven
* A valid selected pad
* Missing pads are recreated
* Duplicate positions are repaired deterministically
* Extra unknown pad files are preserved for recovery, not deleted automatically

---

# 8. Storage layout

## 8.1 File organization

Store each pad separately.

```text
BetterTot/
├── Pads/
│   ├── <pad-uuid>.txt
│   ├── <pad-uuid>.txt
│   └── ...
├── workspace.json
├── Journal/
│   ├── active.log
│   └── recovered/
├── Backups/
│   ├── hourly/
│   ├── daily/
│   └── manual/
└── Diagnostics/
```

Do not hard-code a home-directory path.

Resolve Application Support using `FileManager` and respect the application’s sandbox/container configuration.

## 8.2 Plain-text encoding

Pad files should use:

* UTF-8
* Unix line endings internally
* No byte-order mark
* Atomic replacement
* Preservation of the final newline exactly as entered

Import should accept common UTF encodings where practical, but internal storage should normalize to UTF-8.

## 8.3 Metadata format

Use JSON for small application metadata.

Requirements:

* Explicit schema version
* Stable date encoding
* Human-readable formatting in debug builds
* Atomic replacement
* Validation before replacing the currently loaded state

## 8.4 Atomic writes

The write sequence should be:

1. Encode the new content.
2. Write to a temporary file in the same directory.
3. Flush and close the temporary file.
4. Atomically replace the destination.
5. Update metadata only after the content write succeeds.
6. Retain recoverable state when any step fails.

Pad writes and metadata writes should be serialized through a dedicated storage actor or queue.

```swift
actor WorkspaceStore {
    func loadWorkspace() async throws -> WorkspaceSnapshot
    func savePad(id: PadID, text: String) async throws
    func updateMetadata(_ update: MetadataUpdate) async throws
}
```

---

# 9. Save and recovery model

## 9.1 Normal saves

Use a short debounce, approximately 200 milliseconds.

On each text change:

1. Update in-memory state synchronously.
2. Record the pending revision.
3. Append recoverable information to the journal.
4. Schedule an atomic pad-file write.
5. Mark the journal entry committed after the write succeeds.

Also request immediate save on:

* Pad switch
* Panel dismissal
* Application deactivation
* Sleep notification
* Application termination
* Manual export
* Before changing storage location

## 9.2 Recovery journal

A debounce alone cannot guarantee recovery after a crash or forced termination.

Use an append-only journal containing enough information to restore acknowledged edits.

A simple version can record complete pad snapshots because each scratchpad is expected to remain small.

```swift
struct JournalEntry: Codable {
    let entryID: UUID
    let padID: PadID
    let revision: UInt64
    let timestamp: Date
    let text: String
}
```

Do not prematurely optimize with character-level diffs.

On successful pad write:

* Mark the revision committed, or
* Safely rotate/truncate committed journal entries

On startup after an unclean shutdown:

1. Load the pad file.
2. Read valid journal entries.
3. Select the newest complete revision for each pad.
4. Compare it with persisted metadata.
5. Recover newer uncommitted content.
6. Preserve both versions when correctness is uncertain.
7. Inform the user only when manual review is necessary.

## 9.3 Clean-shutdown marker

At startup:

```text
lastCleanShutdown = false
```

Persist that state early.

During orderly termination:

1. Flush pending writes.
2. Confirm completion.
3. Set `lastCleanShutdown = true`.
4. Atomically save metadata.

The marker is only a recovery hint. It is not proof that every disk write reached permanent storage.

## 9.4 Backup policy

Recommended default retention:

* Latest 20 change snapshots
* One hourly snapshot for the last 24 hours
* One daily snapshot for the last 14 days
* Manual backups retained until the user deletes them

Apply size limits as well as count limits.

Backups should be independently readable text files wherever possible.

## 9.5 Honest reliability requirement

Do not state that data loss is impossible.

Use this requirement:

> BetterTot must preserve committed content and recover the latest journaled edit after ordinary application crashes and forced termination, except where the operating system or storage device fails before data reaches durable storage.

---

# 10. Import and export

## 10.1 Import

Support:

* Import one text file into the selected pad
* Import eight text files into all slots
* Import a BetterTot backup
* Paste as plain text

When importing into a non-empty pad:

* Offer Replace
* Offer Append
* Offer Cancel

Create a backup before replacement.

## 10.2 Export

Support:

* Export current pad as `.txt`
* Export all pads as a directory
* Export a complete BetterTot backup
* Copy complete pad content

Suggested all-pad export:

```text
BetterTot Export/
├── Pad 1.txt
├── Pad 2.txt
├── Pad 3.txt
├── Pad 4.txt
├── Pad 5.txt
├── Pad 6.txt
├── Pad 7.txt
└── metadata.json
```

Do not require BetterTot to read ordinary exported text.

---

# 11. Settings

Version 0.1 settings should remain limited.

## General

* Launch at login
* Global shortcut
* Start pinned or unpinned
* Restore last selected pad
* Confirm before clearing
* Show or hide Dock icon, only if technically supported without destabilizing lifecycle

For modern macOS login-item registration, use `SMAppService`; Apple exposes `mainApp` for registering the main application as a login item. ([Apple Developer][2])

## Editor

* Font family
* Font size
* Line spacing
* Spell checking
* Smart quotes
* Smart dashes
* Automatic link detection
* Automatic text replacement
* Monospaced mode

## Appearance

* Follow system
* Light
* Dark
* Reduce transparency
* Slot indicator style

## Backups

* Open backup directory
* Create backup now
* Restore backup
* Retention summary

Do not expose low-level implementation settings.

---

# 12. Accessibility

Accessibility is part of version 0.1 acceptance, not a later enhancement.

Requirements:

* Complete keyboard operation
* VoiceOver-readable status item
* VoiceOver labels for all eight pads
* Selected-pad state exposed to accessibility APIs
* Logical key-view order
* Configurable text size
* Sufficient contrast
* Reduced-motion support
* No state represented only by color
* Correct accessibility focus when opening
* Proper announcements when changing pads
* Clear labels for pin, clear, export, and settings controls

Suggested labels:

```text
“Scratchpad 1, selected”
“Scratchpad 2, empty”
“Pin scratchpad window”
```

Test with VoiceOver enabled from the beginning.

---

# 13. Privacy and security

## Version 0.1 policy

BetterTot should:

* Make no network requests except an explicit user-initiated update check
* Contain no analytics SDK
* Contain no advertising SDK
* Require no account
* Collect no note content
* Avoid including note text in logs
* Avoid including note text in crash metadata
* Keep diagnostics opt-in
* Clearly document storage paths
* Clearly document that local files are not encrypted by BetterTot

## Logging

Use structured logging only for operational events.

Allowed:

```text
Pad save succeeded
Pad save failed with POSIX error 28
Journal recovery started
Metadata schema migration completed
```

Forbidden:

```text
Saved text: “My password is...”
Current pad contents: ...
Clipboard contents: ...
```

## Encryption

Do not advertise encrypted storage in version 0.1.

A later security release may add:

* Optional Touch ID lock
* Encrypted storage
* Mission Control content hiding
* Automatic clipboard clearing
* Configurable inactivity locking

These require a separate threat model and migration plan.

---

# 14. Application lifecycle

## 14.1 Application type

Use an AppKit application with an application delegate.

Configure it as a menu-bar-oriented application without a normal Dock presence.

The lifecycle controller should own:

* Status item
* Panel controller
* Workspace store
* Shortcut service
* Settings controller
* Application activation policy
* Termination coordination

## 14.2 Startup sequence

1. Resolve storage directory.
2. Acquire a single-instance guard.
3. Initialize logging without note contents.
4. Load and validate metadata.
5. Recover journal if necessary.
6. Repair workspace invariants.
7. Load selected pad.
8. Create status item.
9. Register global shortcut.
10. Register lifecycle notifications.
11. Remain hidden until invoked.

Do not show an empty editor before recovery finishes.

## 14.3 Termination sequence

1. Stop accepting new save requests.
2. Capture the current editor state.
3. Flush the selected pad.
4. Flush pending writes for all pads.
5. Save metadata.
6. Mark clean shutdown.
7. Unregister shortcut.
8. Remove event monitors.
9. Terminate.

Provide a bounded failure path: if a save fails, preserve the journal and do not falsely mark the shutdown clean.

---

# 15. Repository structure

```text
bettertot/
├── BetterTot/
│   ├── Application/
│   ├── MenuBar/
│   ├── Panel/
│   ├── Editor/
│   ├── Workspace/
│   ├── Persistence/
│   ├── Recovery/
│   ├── Shortcuts/
│   ├── ImportExport/
│   ├── Settings/
│   ├── Accessibility/
│   └── Resources/
├── BetterTotTests/
│   ├── Workspace/
│   ├── Persistence/
│   ├── Recovery/
│   └── Migrations/
├── BetterTotUITests/
│   ├── PanelLifecycle/
│   ├── Keyboard/
│   ├── Accessibility/
│   └── CrashRecovery/
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DATA_FORMAT.md
│   ├── RECOVERY.md
│   ├── PRIVACY.md
│   ├── RELEASE.md
│   └── TRADEMARKS.md
├── scripts/
│   ├── build.sh
│   ├── test.sh
│   ├── archive.sh
│   └── checksum.sh
├── .github/
│   ├── ISSUE_TEMPLATE/
│   ├── pull_request_template.md
│   └── workflows/
├── LICENSE
├── NOTICE
├── README.md
└── CONTRIBUTION.md
```

---

# 16. Open-source governance

## License

Recommended license:

```text
Apache License 2.0
```

Reasons:

* Permissive commercial and personal use
* Explicit patent-license provisions
* Familiar contribution model
* Compatible with broad adoption

MIT is also acceptable if maximum simplicity is preferred.

## Contribution requirements

Pull requests should require:

* A clear problem statement
* Tests for behavioral changes
* No collection of note contents
* No new network behavior without explicit architectural review
* Accessibility consideration
* Migration handling for persisted-data changes
* No third-party dependency without justification
* No feature that turns the application into a general note manager without a product decision

## Dependency policy

Prefer no third-party runtime dependencies in version 0.1.

A global-hotkey package may be accepted when:

* It is actively maintained
* It has a compatible permissive license
* Its implementation is small enough to audit
* It does not monitor arbitrary keyboard input
* It can be replaced behind `GlobalShortcutService`

---

# 17. Testing strategy

## 17.1 Unit tests

Test:

* Workspace creation
* Exactly-eight-pad invariant
* Duplicate pad repair
* Missing file recovery
* UTF-8 save/load round trips
* Empty files
* Very large pads
* Atomic write failures
* Disk-full failures
* Permission failures
* Corrupted metadata
* Truncated journal entries
* Journal replay
* Backup retention
* Schema migrations
* Selection clamping
* Unicode and emoji offsets
* Import collision behavior
* Export naming
* Shortcut validation

## 17.2 Integration tests

Test:

* Editor-to-store save flow
* Rapid pad switching
* Save during dismissal
* Save during application deactivation
* Recovery after interrupted write
* Recovery after metadata save but before pad save
* Recovery after pad save but before metadata save
* Concurrent export and editing
* Pin/unpin state preservation

## 17.3 UI tests

Mandatory named regression test:

```swift
func testPressingReturnDoesNotDismissPanel()
```

Test sequence:

1. Open panel.
2. Focus editor.
3. Type text.
4. Press Return.
5. Verify panel remains visible.
6. Verify newline appears.
7. Continue typing.
8. Dismiss panel.
9. Reopen panel.
10. Verify complete content.

Additional UI tests:

```text
testEditorReceivesFocusAfterStatusItemOpen
testEditorReceivesFocusAfterShortcutOpen
testEscapeDismissesUnpinnedPanel
testEscapeDoesNotDestroyText
testOutsideClickDismissesUnpinnedPanel
testOutsideClickDoesNotDismissPinnedPanel
testReturnDoesNotDismissPanel
testShiftReturnDoesNotDismissPanel
testOptionReturnDoesNotDismissPanel
testCommandReturnDoesNotDismissPanel
testUndoDoesNotDismissPanel
testPasteDoesNotDismissPanel
testPadSwitchPreservesText
testPadSwitchRestoresSelection
testPinningDoesNotRecreateEditor
testPanelRepositionsAcrossDisplays
```

## 17.4 Crash tests

Automate where possible:

1. Type content.
2. Confirm journal append.
3. Terminate with `SIGKILL`.
4. Relaunch.
5. Verify recovery.
6. Confirm no duplicate or lost suffix.
7. Confirm the primary pad file remains valid.

Also simulate:

* Truncated JSON
* Truncated journal line
* Missing pad file
* Read-only directory
* Disk-full error
* Interrupted atomic replacement

## 17.5 Manual compatibility matrix

Test:

* Current stable macOS
* Current macOS beta
* Apple Silicon
* Built-in keyboard
* External keyboard
* Multiple keyboard layouts
* Emoji
* Japanese IME
* Chinese IME
* VoiceOver
* Multiple displays
* Notched MacBook display
* Menu-bar auto-hide
* Full-screen applications
* Spaces
* Stage Manager
* Screen sleep and wake
* Fast user switching

---

# 18. Performance requirements

Version 0.1 targets:

* Warm panel opening should appear immediate.
* Typing should never wait for disk writes.
* Pad switching should not display a loading indicator.
* Ordinary saves should run off the main thread.
* Startup should remain fast with all eight pads at expected scratchpad sizes.
* Memory should remain bounded when repeatedly switching pads.
* Event monitors must not remain installed while unnecessary.

Do not optimize for multi-gigabyte notes. BetterTot is a scratchpad, not a large-document editor.

Set a soft warning threshold rather than a destructive hard limit.

Example:

```text
Warn when a pad exceeds 5 MB.
Continue allowing the user to edit and export it.
```

The exact threshold should be based on measurement.

---

# 19. Release and distribution

## Initial distribution

Use:

* A locally built `.app`
* Ad-hoc code signing
* A versioned local ZIP and SHA-256 checksum

Do not publish the current build. Developer ID signing, Apple notarization,
GitHub Releases, and Homebrew distribution are optional future work only if the
distribution scope changes. Apple documents Developer ID signing for software
distributed outside the Mac App Store, and that future path would still require
notarization. ([Apple Developer][3])

## Version 0.1 packaging

Provide:

* Ad-hoc-signed `.app`
* Local `.zip`
* SHA-256 checksum
* Release notes
* Minimum supported macOS version
* Architecture information
* Reproducible build instructions where practical

## Updates

Do not include an automatic updater in version 0.1.

Settings may check public release metadata only after an explicit user action.
The check must use an ephemeral session, disclose its destination, send no note
or workspace data, and validate any release URL before opening it. It must not
run at launch, poll in the background, download an app, or install anything.

For the private/local build, update by replacing the application bundle
manually.

An automatic updater creates network, signing, security, and operational responsibilities that are unnecessary before product validation.

## Sandboxing

Make an explicit decision during Phase 0.

Preferred approach:

* Attempt to operate sandboxed.
* Keep entitlements minimal.
* Validate global shortcut, import/export, login item, and future sync requirements.
* Document any reason the sandbox must be disabled.

Do not couple the domain model to a particular filesystem path.

---

# 20. Future synchronization architecture

Synchronization is not part of version 0.1.

BetterTot now supports a one-way, user-selected iCloud Drive backup mirror.
That safety copy does not synchronize live pads, merge revisions, or change
the conflict model described below.

## Phase-one synchronization option

Start with user-visible files in an iCloud Drive container only after the local storage model is stable.

Concurrent file access should use coordinated file operations; Apple describes `NSFileCoordinator` as coordinating reads and writes among file presenters. ([Apple Developer][4])

## Revision model

Do not resolve conflicts using timestamps alone.

```swift
struct PadRevision: Codable {
    let revisionID: UUID
    let parentRevisionID: UUID?
    let padID: PadID
    let deviceID: UUID
    let createdAt: Date
    let contentHash: String
}
```

When two revisions have the same parent:

* Preserve both
* Mark the pad conflicted
* Never silently choose one
* Provide recovery or merge UI
* Retain original files

## CloudKit

Consider CloudKit only if file-based synchronization cannot satisfy:

* Conflict handling
* Reliability
* Cross-device latency
* Diagnostics
* Future iOS support

Do not introduce CloudKit preemptively.

---

# 21. Development phases

## Phase 0 — Technical spike

Build a disposable proof of concept with one pad.

Required:

* `NSStatusItem`
* Custom key-capable `NSPanel`
* `NSTextView`
* Status-item opening
* Global-shortcut opening
* First-responder restoration
* Return behavior
* Escape dismissal
* Outside-click dismissal
* Pinning
* Basic local persistence
* Multiple-display positioning

Exit criteria:

* Return never dismisses the panel in repeated automated testing.
* The editor receives focus every time.
* Pinning does not recreate the editor.
* Outside-click behavior is deterministic.
* The implementation works on stable and beta macOS test machines.

Do not continue if the panel architecture remains unreliable.

## Phase 1 — Storage foundation

Implement:

* Stable pad IDs
* One file per pad
* Workspace metadata
* Atomic writes
* Serialized storage actor
* Journal
* Recovery
* Backups
* Storage-error handling

Exit criteria:

* Content survives forced termination.
* Corrupted metadata does not destroy pad text.
* An individual damaged pad does not damage the other seven.
* Failed saves are visible and recoverable.

## Phase 2 — Eight-pad MVP

Implement:

* Eight fixed pads
* Pad indicators
* Keyboard switching
* Selection restoration
* Scroll restoration
* Copy and clear actions
* Empty-state behavior
* Pad naming and optional color

Exit criteria:

* Rapid switching cannot lose edits.
* Each pad persists independently.
* All operations are keyboard accessible.

## Phase 3 — Product completion

Implement:

* Settings
* Font controls
* Launch at login
* Import/export
* Backup browser
* Appearance modes
* Accessibility polish
* Privacy documentation
* Diagnostics without note content

Exit criteria:

* Complete version 0.1 feature set
* VoiceOver acceptance
* Import/export round-trip tests
* No known P0 defects

## Phase 4 — Release engineering

Implement:

* Release build configuration
* Ad-hoc signing
* Local packaging
* Checksums
* Release documentation

Exit criteria:

* Local installation succeeds
* Upgrade preserves all notes
* Uninstall instructions are documented

Developer ID signing, notarization, tagged GitHub releases, clean-Mac
Gatekeeper acceptance, and Homebrew are not Phase 4 exit criteria for the
private/local scope.

## Phase 5 — Post-release hardening

Prioritize:

* Crash reports submitted manually by users
* Beta macOS regressions
* Input-method bugs
* Multiple-display bugs
* Data-recovery problems
* Accessibility defects

Do not prioritize feature expansion over reliability.

---

# 22. Issue priorities

## P0 — Release blockers

* Return dismisses panel
* Editor fails to receive focus
* Text loss
* Corruption of multiple pads
* Recovery failure
* Panel inaccessible after display change
* Global shortcut captures ordinary typing
* Application cannot open after malformed metadata
* Export produces incomplete content
* Accessibility prevents basic operation

## P1 — Required for a strong release

* Selection restoration errors
* Scroll restoration errors
* Shortcut conflict handling
* Pinning inconsistencies
* Backup restore issues
* Launch-at-login errors
* Appearance defects
* High CPU usage
* Event-monitor leaks

## P2 — Post-release improvements

* [x] Markdown list continuation
* [x] Native inline checkboxes with Markdown-backed persistence
* Syntax highlighting
* Shortcuts.app actions
* URL scheme
* Command-line helper
* Optional automatic updater
* iCloud synchronization
* iOS companion

## Out of scope unless product direction changes

* Folders
* Tags
* Search-heavy knowledge management
* Collaboration
* AI writing
* Web application
* Plugin marketplace

---

# 23. Version 0.1 definition of done

Version 0.1 is complete only when all of the following are true:

## Window behavior

* Status-item click opens the panel.
* Global shortcut opens the panel.
* Editor receives focus every time.
* Return inserts a newline.
* No normal editor command dismisses the panel.
* Escape dismisses only when appropriate.
* Outside click dismisses only an unpinned panel.
* Pinning retains the active editor and state.
* Panel placement works across supported display configurations.

## Persistence

* Eight pads persist independently.
* Rapid switching does not lose edits.
* Forced termination recovers the latest journaled content.
* Corrupted metadata does not destroy note files.
* Missing files are handled safely.
* Disk-write errors are surfaced.
* Backups can be restored.
* Exported text is readable without BetterTot.

## Accessibility

* Every action is keyboard accessible.
* VoiceOver identifies all pad selectors.
* Selected state is announced.
* Color is not the only state indicator.
* Text size is configurable.
* Focus moves correctly when the panel opens.

## Privacy

* No note contents appear in logs.
* No network request occurs without an explicit update-check action.
* No analytics or advertising dependency is present.
* Storage and backup behavior are documented.

## Distribution

* Release is ad-hoc signed for private/local use.
* Local installation works on the target Mac.
* Upgrade preserves existing data.
* Release artifacts have checksums.

## Testing

* Unit, integration, UI, crash-recovery, and accessibility suites pass.
* The Return-key regression test passes repeatedly.
* Stable and beta macOS smoke tests pass.
* No unresolved P0 defect remains.

---

# 24. Recommended implementation order

```text
1. Create AppKit LSUIElement application
2. Add NSStatusItem
3. Build custom key-capable NSPanel
4. Add one NSTextView
5. Establish deterministic first-responder behavior
6. Implement explicit dismissal controller
7. Add outside-click handling
8. Add pinned mode
9. Add panel positioning across displays
10. Add one-pad atomic storage
11. Add recovery journal
12. Add crash-recovery tests
13. Add global shortcut abstraction
14. Add eight-pad model
15. Add pad-switch keyboard commands
16. Add selection and scroll restoration
17. Add backups
18. Add import/export
19. Add settings
20. Add launch at login
21. Add accessibility
22. Complete test matrix
23. Add ad-hoc local packaging
24. Gather reliability feedback
25. Consider public distribution only if product scope changes
26. Consider Markdown conveniences
27. Consider synchronization
```

---

# 25. Immediate first milestone

The first milestone is not “eight notes.”

It is:

> A one-note AppKit prototype whose menu-bar-attached panel always focuses correctly, accepts Return normally, dismisses only through explicit paths, survives forced termination, and can be pinned without recreating the editor.

Until that milestone is reliable, no additional product features should be built.

That interaction is BetterTot’s core technical risk and its primary competitive value.

The right starting point is Phase 0. Do not begin with synchronization, Markdown, branding polish, or all eight pads.

---

# 26. Planned next phase: iCloud-only backups and command menus

This phase replaces the optional local-to-iCloud mirror with one automatic,
app-owned iCloud backup repository. It also moves every backup command into
Settings and makes the application and status menus useful for scratchpad work.

This is backup synchronization, not live pad synchronization. Pad files,
journals, and recovered edits remain local. Normal editing and saving must
continue when iCloud is unavailable. These local journal and recovery files are
implementation safeguards, not an optional local backup destination. BetterTot
must expose exactly one backup repository: iCloud Drive.

## 26.1 Destination decision

The current private build is ad-hoc signed and has no Apple Team ID or iCloud
entitlements. For that build, resolve the visible iCloud Drive directory from
the current user's home directory and use this fixed child folder:

```text
~/Library/Mobile Documents/com~apple~CloudDocs/
  BetterTot Backups (org.bettertot.BetterTot)/
```

The display name and bundle identifier are fixed constants, not localized or
derived from the running bundle. This makes the folder name human-readable,
unique, and deterministic across BetterTot versions on the same iCloud account.
There is no folder picker, enable switch, or persisted destination preference.

The repository lives outside `BetterTot.app`, application caches, temporary
directories, and local preferences. Replacing or updating the app bundle must
not move, recreate, or delete it. Deleting and reinstalling the app must resolve
the same path, read the existing ownership manifest, and continue from the
existing snapshots without requiring remembered `UserDefaults`.

The folder name, repository identifier, and schema contract are stable storage
identities. Do not include the application version, build number, architecture,
installation path, or localized app name in any of them. A future rename must
keep resolving this original repository unless an explicit, verified migration
is implemented.

Access to `com~apple~CloudDocs` is an implementation detail suitable only for
the current non-sandboxed private build. Isolate it behind an
`ICloudBackupLocationResolving` boundary. Once Apple developer authorization is
available, replace that resolver with
`FileManager.url(forUbiquityContainerIdentifier:)` and the app-owned container
`iCloud.org.bettertot.BetterTot`; do not change the repository or Settings
contracts during that migration.

Never create the `Mobile Documents` or `com~apple~CloudDocs` ancestors. If the
iCloud Drive root does not already exist as a writable directory, report iCloud
as unavailable.

## 26.2 Repository ownership and validation

The deterministic folder contains a versioned ownership manifest:

```json
{
  "format": "org.bettertot.backup-repository",
  "schemaVersion": 1,
  "bundleIdentifier": "org.bettertot.BetterTot",
  "repositoryIdentifier": "org.bettertot.BetterTot.backups"
}
```

Use `Codable` for the manifest. Write it atomically before publishing the first
snapshot. The repository may contain only the manifest, documented migration
state, and the BetterTot backup hierarchy.

Preflight states:

| Existing state | Result |
|---|---|
| Folder absent | Create it and its manifest atomically |
| Folder empty | Adopt it by writing the manifest |
| Valid manifest and valid layout | Continue |
| Recognizable legacy BetterTot layout | Migrate non-destructively, then claim it |
| Wrong/missing manifest plus unknown content | Block all writes and pruning |
| Symlink, regular file, malformed hierarchy, or newer schema | Block all writes and pruning |

Validation must never rename, delete, or overwrite unknown content. Startup
preflight validates structure and names without forcing every iCloud placeholder
to download. Snapshot contents and hashes are validated when restoring.

Each completed snapshot gets a manifest with its kind, creation date,
installation ID, expected files, byte sizes, and SHA-256 hashes. The
installation ID is a random UUID persisted by BetterTot; never derive it from
hardware or account identifiers. Retention is applied per installation so one
Mac cannot prune another Mac's snapshots. Repository discovery never depends
on that locally persisted UUID: if a full reinstall loses it, BetterTot creates
a new installation record while preserving and displaying every previous
installation's snapshots.

## 26.3 When to tell the user

Run the first preflight asynchronously after the status item, menus, panel, and
Settings controller are ready, but before migration or the first backup write.

If the deterministic folder exists and contains invalid or foreign items:

1. Mark iCloud backup as blocked and make no filesystem changes.
2. Add an `iCloud Backup Needs Attention` status-menu item that opens Storage.
3. Show a persistent warning in Settings > Storage with the exact folder path.
4. Present one alert per launch after application setup, never while a backup
   or editor operation is in progress. Offer `Open Folder` and `Open Storage
   Settings`; dismissal does not authorize adoption or deletion.
5. Revalidate when Storage opens and before every backup, prune, or restore.
   Do not repeat the alert within the same launch unless the conflict changes.

Use the same persistent status for unavailable iCloud Drive, but do not describe
an unavailable root as invalid content. Logs include only error domain, code,
and repository state; never log note text or foreign filenames.

## 26.4 Backup execution and migration

Replace local rolling snapshots plus mirroring with a `BackupRepository` actor
that owns validation, coordinated iCloud I/O, publication, and retention.
`WorkspaceStore` captures an immutable, internally consistent snapshot and
hands it to that actor. Publishing uses a hidden temporary sibling, verifies
the completed snapshot, then moves it into place. Pad commits must not wait for
background hourly or daily publication.

`Back Up Now`, destructive import safety backups, and restore safety backups do
await verified publication. If iCloud is unavailable, those safety-dependent
operations stop without changing current pad data.

The upgrade migration is resumable and idempotent:

1. Validate and claim the deterministic iCloud repository.
2. Copy existing local backups.
3. Copy the previously selected mirror, if configured.
4. Deduplicate byte-identical snapshots; preserve differing same-name snapshots
   with a deterministic hash suffix.
5. Verify every copied snapshot before recording migration completion.
6. Only then route future backups exclusively to iCloud.

Never delete old local backups or the former user-selected mirror during this
phase. They become untouched migration source data, not a selectable fallback,
destination, or ongoing backup option. No new local rolling snapshots are
created after the verified iCloud cutover.

## 26.5 Settings > Storage

Remove the mirror switch, folder chooser, local backup destination row, and all
language describing a second copy. The Storage page becomes the only backup
control surface and contains:

* iCloud availability and repository health
* Deterministic folder path
* Hourly, daily, and manual snapshot counts
* Migration progress or conflict status
* `Back Up Now`
* `Restore Backup...`
* `Open in iCloud Drive`
* Automatic health refresh when Settings opens or regains focus

Disable backup and restore commands while the repository is unavailable,
invalid, migrating, or busy. `Open Folder` remains enabled for invalid-content
recovery when the path exists. Settings backup actions must call through the
panel controller so pending editor text is committed before snapshot capture.

## 26.6 Menus

Remove `Create Backup Now`, `Open Backup Folder`, and `Restore Backup...` from
the status menu. Backup health may appear there only as the conditional
attention item described above.

Recommended status menu:

```text
Show/Hide BetterTot
Pin/Unpin Scratchpad
Scratchpads >
Copy Entire Pad
Import/Export >
Settings...
Quit BetterTot
```

`Scratchpads` lists all eight current pad names, checks the selected pad, and
supports direct selection. `Import/Export` contains import into current pad,
export current pad, and export all pads. Do not put destructive clear in the
status menu while the pad content is hidden.

The main menu adds:

* `File`: import and export commands
* `Scratchpad`: show/hide, pin/unpin, previous/next, direct pad selection, and
  copy entire pad
* `Format`: bulleted list, numbered list, and checklist

Use one command-routing layer for the main and status menus. Dynamic titles,
enabled states, and selected-pad checkmarks use menu validation rather than
duplicated menu state.

## 26.7 Implementation order

1. Add resolver, repository state, manifest, and validator tests.
2. Implement the deterministic private-build resolver and iCloud-unavailable
   states behind dependency injection.
3. Implement atomic repository publication, verification, cancellation, and
   per-installation retention.
4. Implement resumable migration without deleting legacy data.
5. Cut backup creation, counts, and restore over to the repository actor.
6. Rebuild Storage around repository health and backup actions.
7. Introduce shared menu command routing and remove backup menu commands.
8. Update SPEC, README, privacy documentation, and manual testing.
9. Run the complete automated suite once, then perform signed-in, offline,
   signed-out, invalid-folder, migration, and second-Mac manual checks.

## 26.8 Release gates

Required automated coverage:

* Deterministic path resolution and missing/unwritable iCloud roots
* Empty, valid, legacy, foreign, malformed, symlinked, and newer-schema folders
* Proof that invalid content causes zero writes, moves, or deletions
* Atomic publication, hash verification, collision handling, and cancellation
* Per-installation retention and two-installation isolation
* Resumable and interrupted migration with legacy preservation
* Upgrade by replacing the app bundle while preserving the repository
* Fresh installation with empty preferences rediscovering existing snapshots
* Reinstall receiving a new installation ID without hiding or pruning old data
* Pad saving while iCloud is unavailable
* Safety backup enforcement before replace and restore
* Storage states and exact main/status menu contents and actions
* Existing macOS 13 compatibility and current macOS visual snapshots

The private-build resolver may ship only for the existing non-sandboxed local
distribution. Public, sandboxed, or multi-user distribution requires an
entitlement-backed ubiquity container and development-signed validation first.

## 26.9 Release target and ticket acceptance

The release version is **BetterTot 0.3.0**. This is a minor pre-1.0 increment
because the release replaces the backup architecture and adds new menu command
surfaces without intentionally breaking the eight-pad workspace format. Reserve
`0.3.1` for stabilization fixes found after the cutover.

| Ticket # | Ticket Tagline | Acceptance Criteria |
|---|---|---|
| BT-030-01 | Freeze the iCloud repository identity | The root resolves to `iCloud Drive/BetterTot Backups (org.bettertot.BetterTot)` for every build and version; no version, localization, architecture, or installation path changes it; no folder picker or destination preference exists. |
| BT-030-02 | Resolve iCloud availability safely | A present writable CloudDocs root resolves successfully; missing, non-directory, symlinked, or unwritable roots return explicit unavailable states; BetterTot never creates the `Mobile Documents` or `com~apple~CloudDocs` ancestors. |
| BT-030-03 | Claim the repository with a manifest | An absent or empty app folder receives one atomically written schema-v1 ownership manifest; a matching manifest is accepted; wrong ownership or a newer schema blocks access without modifying the folder. |
| BT-030-04 | Reject foreign and malformed contents | Unknown root items, malformed tiers, unexpected snapshot files, and symlinks produce a blocked state; automated tests prove the failed preflight performs zero writes, moves, overwrites, prunes, or deletions. |
| BT-030-05 | Surface repository conflicts at the correct time | Preflight runs after menus, panel, and Settings are ready but before migration or backup writes; a conflict produces a persistent Storage warning, an `iCloud Backup Needs Attention` menu item, and at most one alert per launch unless the conflict fingerprint changes. |
| BT-030-06 | Define immutable snapshot manifests | Every snapshot records kind, creation date, installation ID, expected files, byte sizes, and SHA-256 hashes; manifests encode and decode with `Codable`; note contents and filenames never enter diagnostic logs. |
| BT-030-07 | Publish snapshots atomically | Publication writes to a hidden temporary sibling, verifies files and hashes, and moves into place only when complete; cancellation or failure leaves no visible partial snapshot and never overwrites an existing snapshot. |
| BT-030-08 | Isolate retention between installations | Hourly retains 24 and daily retains 14 snapshots per installation; manual snapshots are not automatically pruned; one installation cannot prune another installation's snapshots; installation IDs never use hardware or account identifiers. |
| BT-030-09 | Cut over to iCloud-only backups | After migration verification, hourly, daily, manual, import-safety, and restore-safety snapshots publish only to the iCloud repository; no new local rolling snapshot is created; local journals continue solely as crash-recovery infrastructure. |
| BT-030-10 | Migrate legacy backups without loss | Existing local backups are copied before the previous mirror; migration is resumable and idempotent; byte-identical snapshots deduplicate; different same-name snapshots receive deterministic hash suffixes; source data is never deleted automatically. |
| BT-030-11 | Survive updates and reinstalls | Replacing or updating `BetterTot.app` preserves and rediscovers all snapshots; a fresh installation with empty preferences finds the repository from its fixed path and manifest; a new installation ID does not hide or prune snapshots from previous installations. |
| BT-030-12 | Keep editing independent of iCloud | Pad saves, journals, switching, launch, and termination work while iCloud is unavailable; `Back Up Now` reports failure without changing pad data; destructive import or restore stops before mutation when its verified safety snapshot cannot be published. |
| BT-030-13 | Make Storage the backup control center | Storage shows repository health, fixed path, counts, migration state, and actionable errors; it contains `Back Up Now`, `Restore Backup...`, and `Open in iCloud Drive`, and refreshes health when Settings opens or regains focus; there is no local destination, mirror switch, or folder chooser. |
| BT-030-14 | Route Settings backup actions through live editor state | `Back Up Now` and restore first commit pending text from every edited pad; controls disable while unavailable, invalid, migrating, or busy; invalid-folder recovery can still open the existing folder. |
| BT-030-15 | Share one menu command router | Main and status menus invoke one command layer; titles, enabled states, selected pad checkmarks, and pin state update through menu validation; command behavior matches keyboard and footer actions. |
| BT-030-16 | Replace status-menu backup commands with useful tools | The status menu contains show/hide, pin/unpin, eight named scratchpads, copy entire pad, grouped import/export, Settings, and Quit; it contains no create/open/restore backup command; destructive clear is absent. |
| BT-030-17 | Add complete main-menu commands | `File` exposes import/export, `Scratchpad` exposes visibility, pinning, navigation, selection, and copy-all, and `Format` exposes bulleted, numbered, and checklist actions; standard Edit behavior remains intact. |
| BT-030-18 | Update the product contract | `SPEC.md`, README, privacy documentation, manual testing, and uninstall/update guidance describe iCloud as the only backup repository, disclose the private-build CloudDocs path, and distinguish crash recovery from backups. |
| BT-030-19 | Pass the 0.3.0 release gate | The complete automated suite passes the 80% coverage gate; release and installer checks pass; manual signed-in, offline, signed-out, invalid-folder, interrupted-migration, app-update, app-reinstall, and second-Mac checks are recorded before tagging `v0.3.0`. |

[1]: https://developer.apple.com/documentation/appkit/nswindow/canbecomekey?utm_source=chatgpt.com "canBecomeKey | Apple Developer Documentation"
[2]: https://developer.apple.com/documentation/servicemanagement/smappservice?utm_source=chatgpt.com "SMAppService | Apple Developer Documentation"
[3]: https://developer.apple.com/developer-id/?utm_source=chatgpt.com "Signing Mac Software with Developer ID - Apple Developer"
[4]: https://developer.apple.com/documentation/foundation/nsfilecoordinator?utm_source=chatgpt.com "NSFileCoordinator | Apple Developer Documentation"
