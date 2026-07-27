# BetterTot — development prototype

Native macOS menu-bar scratchpad (plan phases 0–3 implemented): seven fixed
pads, custom key-capable `NSPanel` + `NSTextView`, crash-recovery journal,
rolling backups, import/export, settings, local-first storage in
`~/Library/Application Support/BetterTot/`:

```text
BetterTot/
├── Pads/<pad-uuid>.txt        # one UTF-8 file per pad, atomic writes
├── workspace.json             # metadata (positions, selection, revisions)
├── Journal/
│   ├── <pad-uuid>.log         # append-only JSONL, cleared on commit
│   └── recovered/             # pre-recovery file versions, kept forever
└── Backups/
    ├── hourly/                # newest 24, taken on write activity
    ├── daily/                 # newest 14
    └── manual/                # kept until you delete them
```

## Run

```sh
swift run                  # run directly
scripts/bundle.sh          # build dist/BetterTot.app (enables launch at login)
scripts/test.sh            # tests plus the enforced 80% line-coverage gate
```

## Menu

Right-click the menu-bar icon for: Settings (⌘,), backups (create / open
folder / restore), and import/export (current pad or all pads as plain
`Pad N.txt` files). Importing into a non-empty pad offers Replace (after an
automatic backup) or Append; imports are undoable.

## Keys

| Key | Action |
|---|---|
| ⌥⌘Space | Toggle panel (global, configurable in Settings) |
| ⌘1 … ⌘7 | Select pad |
| ⌘← / ⌘→ | Previous / next pad |
| ⇧⌘C | Copy entire pad |
| ⇧⌘⌫ | Clear pad (undoable) |
| Esc | Dismiss (unpinned only) |
| Drag panel background | Pin at the dragged position |
| ⌘P | Keyboard pin / unpin fallback |
| ⌘W | Close attached or pinned panel |
| ⌘Q | Quit |
| ⌘Z / ⇧⌘Z / ⌘X / ⌘C / ⌘V / ⌘A | Standard editing (per-pad undo stacks) |

Note: ⌘←/⌘→ switch pads per the plan (§4.3), which shadows the default
line-start/line-end caret navigation inside the editor.

## Save model

Every keystroke appends a full-text snapshot to the pad's journal; a 200 ms
debounce then commits the pad file atomically and clears the journal. On
launch, any journal entry newer than the committed revision is recovered and
the previous file version is preserved under `Journal/recovered/`. Corrupted
`workspace.json` is kept as `workspace.json.corrupt` and rebuilt by adopting
the existing pad files — metadata damage never costs note text.

## Docs

- [Privacy](docs/PRIVACY.md) — what is stored where, and what is never collected.
- [Release runbook](docs/RELEASE.md) — local packaging, installation, upgrades,
  and optional future public distribution.

## License

BetterTot is licensed under the [Apache License 2.0](LICENSE). See
[NOTICE](NOTICE) for project attribution.

## Release artifact

```sh
scripts/release.sh
```

This builds and verifies a universal, ad-hoc-signed ZIP for local testing.
The current distribution scope is private/local use, so this ad-hoc artifact is
the final package and Apple notarization is not required. Do not redistribute
it as an identified-developer build. Developer ID signing and notarization are
documented only as an optional future path.

## Manual test checklist

- [ ] Return inserts a newline, never dismisses the panel
- [ ] Editor is focused every time (status item open and shortcut open)
- [ ] Esc dismisses only an unpinned panel; text survives
- [ ] Outside click dismisses only an unpinned panel
- [ ] Clicking the menu-bar icon while open closes once and does not reopen
- [ ] Dragging the panel background pins it at the dragged position
- [ ] The pin button beside Settings reflects both click-to-pin and
      drag-to-pin state
- [ ] Pinning does not recreate the editor (undo history survives pin/unpin)
- [ ] Seven pad selectors appear as distinct colored rings; the active pad is
      filled and selection remains visible without relying on color alone
- [ ] The close button dismisses both modes; reopening after closing a pinned
      panel returns it beneath the menu-bar icon
- [ ] The Settings gear closes the attached popover and opens Settings
- [ ] The footer reports live line, word, and character counts plus local-save
      status
- [ ] Type, then `kill -9` immediately → text recovered on relaunch
- [ ] Rapid ⌘1…⌘7 cycling while typing never loses or crosses text
- [ ] Undo after switching pads never edits the wrong pad
- [ ] Selection and scroll position restored per pad
- [ ] Panel positions correctly on a second display / near screen edge
- [ ] Japanese/Chinese IME composition works; Esc cancels composition, not the panel
- [ ] Settings → Global shortcut: record a new chord, confirm it works globally
      and survives relaunch; plain letters beep instead of being accepted
- [ ] Start recording, then click into a pinned pad — typing goes into the note,
      not the recorder, and recording ends
- [ ] Try recording a chord another app owns (e.g. ⌘Space) → actionable alert,
      previous shortcut still works
- [ ] VoiceOver: pad switches announce "Scratchpad N" (and ", empty"); the
      editor reports the selected pad; every control is reachable and labelled
