# Privacy

BetterTot is local-first. The app:

- Checks public GitHub release metadata at most once per 24 hours in bundled builds.
- Contains **no analytics, telemetry, or advertising** code or SDKs.
- Requires **no BetterTot account**. iCloud backup requires iCloud Drive.
- Does not collect or transmit note content.

These statements describe BetterTot's own networking. BetterTot writes rolling
backup files to its deterministic iCloud Drive folder, and macOS may upload
those files under your iCloud settings.

## Update checks

Bundled semantic-version builds contact `api.github.com` at launch when no
successful automatic check has completed in the previous 24 hours. You can
also press **Check for Updates** in Settings at any time. The request asks for
the latest published BetterTot release and includes the installed app version
in the standard `User-Agent` header. GitHub also receives ordinary connection
metadata such as your IP address.

The request uses an ephemeral session with no cookies or persistent response
cache. BetterTot sends no note text, settings, shortcuts, file paths, device
identifier, analytics identifier, or backup data. BetterTot never downloads or
installs an update automatically. When a newer release exists, BetterTot can
open its validated `https://github.com/` release page in your browser.

## Writing Tools and Siri

Apple Writing Tools and Siri integration is disabled by default. When you
enable it in Editor settings, the scratchpad participates in the writing-tools
service provided by macOS. BetterTot does not make that service request or add
its own network transmission; any processing and network use are controlled by
macOS, your Apple settings, and Apple's applicable privacy terms.

## iCloud Drive backups

BetterTot stores hourly, daily, and manual snapshots only in:

```text
~/Library/Mobile Documents/com~apple~CloudDocs/
  BetterTot Backups (org.bettertot.BetterTot)/
```

There is no folder picker, enable switch, local backup destination, or backup
mirror. The backup files contain note text and workspace metadata in readable
form. Hourly snapshots retain the newest 24, daily snapshots retain the newest
14, and manual snapshots remain until you remove them. Unknown files or an
invalid ownership manifest block writes and pruning; BetterTot does not delete
or adopt the unknown content.

The current private, non-sandboxed build accesses the visible iCloud Drive
folder directly and does not use CloudKit. macOS and iCloud Drive control
upload, account access, and network behavior. Editing and local crash recovery
continue when iCloud Drive is unavailable.

When upgrading from the former local/mirror design, BetterTot copies recognized
legacy snapshots after iCloud becomes available and never deletes the source.
Until then those legacy folders remain accessible directly in Finder, but they
are not exposed as a second backup destination in Settings.

## Where your data lives

Everything is plain files on your Mac, readable without BetterTot:

| Path (under `~/Library/Application Support/BetterTot/`) | Contents |
|---|---|
| `Pads/<uuid>.txt` | One UTF-8 text file per scratchpad |
| `workspace.json` | Pad order, selection, revision metadata — never note text |
| `Journal/<uuid>.log` | Crash-recovery snapshots of recent edits; cleared once the pad file is saved |
| `Journal/recovered/` | Pre-recovery file versions, kept until you delete them |

Rolling backups live in the separate iCloud Drive path documented above.

Settings (font, toggles, global shortcut) are stored in the standard
`UserDefaults` preferences for the app. The timestamp of the last successful
automatic update check is stored there to enforce the 24-hour interval.

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

Because of the crash journal, `Journal/recovered/`, and iCloud backups,
text you deleted from a pad may persist on disk in those locations until
their retention expires or you remove them. "Clear pad" clears the pad, not
history. A future release may add an explicit "erase history" action.
