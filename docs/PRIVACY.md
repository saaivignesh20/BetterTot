# Privacy

BetterTot is local-first and offline by default. The app:

- Makes no background or automatic network requests.
- Contains **no analytics, telemetry, or advertising** code or SDKs.
- Requires **no account**.
- Does not collect or transmit note content.

These statements describe BetterTot's own networking. If you enable the
optional iCloud Drive backup mirror, BetterTot writes backup files to the
folder you select and macOS may upload those files under your iCloud settings.

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

## Writing Tools and Siri

Apple Writing Tools and Siri integration is disabled by default. When you
enable it in Editor settings, the scratchpad participates in the writing-tools
service provided by macOS. BetterTot does not make that service request or add
its own network transmission; any processing and network use are controlled by
macOS, your Apple settings, and Apple's applicable privacy terms.

## iCloud Drive backup mirror

The mirror is off by default and requires an explicit folder selection in
Settings. BetterTot keeps its local hourly, daily, and manual recovery backups,
then copies completed backup folders into `BetterTot Backups` inside the
selected folder. The mirrored files contain note text and workspace metadata
in the same readable format as local backups. Mirrored hourly and daily
snapshots follow the same rolling retention limits as their local copies;
manual snapshots remain until you remove them.

BetterTot does not use CloudKit, create an app-specific iCloud container, or
receive data from iCloud. macOS and iCloud Drive control upload, retention,
account access, and network behavior. Turning the mirror off stops future
copies but does not delete files already present in iCloud Drive.

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
`UserDefaults` preferences for the app. The selected backup-mirror path and its
enabled state are stored there as well.

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
