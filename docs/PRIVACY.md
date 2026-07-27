# Privacy

BetterTot is local-first and offline by default. The app:

- Makes no background or automatic network requests.
- Contains **no analytics, telemetry, or advertising** code or SDKs.
- Requires **no account**.
- Does not collect or transmit note content.

## Update checks

BetterTot contacts `api.github.com` only after you press **Check for Updates**
in Settings. The request asks for the latest published BetterTot release and
includes the installed app version in the standard `User-Agent` header. GitHub
also receives ordinary connection metadata such as your IP address.

The request uses an ephemeral session with no cookies or persistent response
cache. BetterTot sends no note text, settings, shortcuts, file paths, device
identifier, analytics identifier, or backup data. It does not check at launch,
download an update, or install anything. When a newer release exists, BetterTot
can open its validated `https://github.com/` release page in your browser.

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
