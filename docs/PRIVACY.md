# Privacy

BetterTot is local-first. The default build:

- Makes **no network requests** of any kind.
- Contains **no analytics, telemetry, or advertising** code or SDKs.
- Requires **no account**.
- Collects **nothing**.

## Where your data lives

Everything is plain files on your Mac, readable without BetterTot:

| Path (under `~/Library/Application Support/BetterTot/`) | Contents |
|---|---|
| `Pads/<uuid>.txt` | One UTF-8 text file per scratchpad |
| `workspace.json` | Pad order, selection, revision metadata — never note text |
| `Journal/<uuid>.log` | Crash-recovery snapshots of recent edits; cleared once the pad file is saved |
| `Journal/recovered/` | Pre-recovery file versions, kept until you delete them |
| `Backups/{hourly,daily,manual}/` | Rolling plain-text backups |

Settings (font, toggles, global shortcut) are stored in the standard
`UserDefaults` preferences for the app.

## Logging

Operational events only (e.g. "pad save failed with POSIX error 28").
**Note content, clipboard content, and file contents never appear in logs**
— this is enforced as a contribution requirement, not just a habit.

## Encryption

BetterTot does **not** encrypt its files. They are protected exactly as well
as the rest of your home directory (FileVault, file permissions, your
backups). Do not store secrets in a scratchpad expecting BetterTot to
protect them.

## Journal and backups outlive deletion

Because of the crash journal, `Journal/recovered/`, and rolling backups,
text you deleted from a pad may persist on disk in those locations until
their retention expires or you remove them. "Clear pad" clears the pad, not
history. A future release may add an explicit "erase history" action.
