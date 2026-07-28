<p align="center">
  <img src="./Assets/AppIcon.svg" alt="BetterTot app icon" width="128">
</p>

<h1 align="center">BetterTot</h1>

<p align="center">
  <strong>A fast, local-first scratchpad for the macOS menu bar.</strong>
</p>

<p align="center">
  <a href="https://github.com/saaivignesh20/BetterTot/actions/workflows/ci.yml"><img alt="CI status" src="https://github.com/saaivignesh20/BetterTot/actions/workflows/ci.yml/badge.svg"></a>
  <a href="./LICENSE"><img alt="Apache 2.0 license" src="https://img.shields.io/badge/license-Apache%202.0-blue.svg"></a>
  <img alt="macOS 13 or later" src="https://img.shields.io/badge/macOS-13%2B-black?logo=apple">
  <img alt="development preview" src="https://img.shields.io/badge/status-development%20preview-orange">
</p>

<p align="center">
  <img src="./Assets/BetterTot-screenshot.png" alt="BetterTot scratchpad showing its seven color-coded pads" width="720">
</p>

BetterTot keeps seven lightweight text pads one shortcut away. It is a native
AppKit application with no account, analytics, or cloud storage.

> [!IMPORTANT]
> BetterTot is currently distributed as a private, ad-hoc-signed development
> preview. There is no public download or notarized release yet.

## Quick Start

Requires macOS 13 or later and a compatible Xcode toolchain.

```sh
git clone https://github.com/saaivignesh20/BetterTot.git
cd BetterTot
scripts/bundle.sh
open dist/BetterTot.app
```

Move `BetterTot.app` to `/Applications` if you want Launch at Login to work
reliably.

## Features

- Seven color-coded scratchpads available from the menu bar
- Global, configurable keyboard shortcut
- Pinning by dragging, with position restored between launches
- Per-pad undo history, selection, and scroll position
- Automatic continuation for bullets and plain-text Markdown checkboxes
- Crash recovery through an append-only journal
- Atomic saves and rolling hourly, daily, and manual backups
- Plain-text import and export
- Native settings for behavior, editing, storage, and updates
- Explicit, manual-only checks for GitHub release metadata

## Keyboard Shortcuts

| Shortcut | Action |
|---|---|
| `Option-Command-Space` | Toggle BetterTot |
| `Command-1` ... `Command-7` | Select a pad |
| `Command-Left` / `Command-Right` | Select the previous / next pad |
| `Shift-Command-C` | Copy the entire pad |
| `Shift-Command-Delete` | Clear the pad |
| `Command-P` | Pin or unpin |
| `Command-W` | Close the panel |
| `Escape` | Dismiss an unpinned panel |

Standard macOS editing shortcuts remain available. The pad-switching shortcuts
take precedence over line-start and line-end navigation in the editor.

## Data and Privacy

BetterTot stores its data in:

```text
~/Library/Application Support/BetterTot/
├── Pads/              # one UTF-8 file per pad
├── Journal/           # crash-recovery snapshots
├── Backups/           # hourly, daily, and manual backups
└── workspace.json     # pad metadata and UI state
```

The app makes no automatic network requests. Choosing **Check for Updates**
sends the installed version in a request to GitHub's public Releases API; note
text, settings, paths, and backup data are never sent. See the complete
[privacy documentation](docs/PRIVACY.md).

## Development

```sh
swift run                  # run from source
scripts/test.sh            # tests and the enforced 80% coverage gate
scripts/bundle.sh          # build an ad-hoc-signed app bundle
scripts/release.sh         # build and verify the local release ZIP
```

The test suite covers persistence, recovery, backups, imports, shortcuts,
settings, update checks, and release tooling. See [SPEC.md](SPEC.md) for the
implemented behavior and architecture, and [PLAN.md](PLAN.md) for project
history and future phases.

## Documentation

- [Contributing](CONTRIBUTION.md)
- [Manual testing](docs/MANUAL_TESTING.md)
- [Privacy](docs/PRIVACY.md)
- [Local release runbook](docs/RELEASE.md)

## License

Licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for
attribution.
