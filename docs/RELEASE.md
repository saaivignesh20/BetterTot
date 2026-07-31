# BetterTot Release Runbook

BetterTot currently ships only as an ad-hoc-signed macOS application. Tagged
builds are stored as repository-scoped GitHub Actions artifacts; the workflow
does not use Apple credentials, notarize the app, create a GitHub Release, or
publish a Homebrew Cask.

## Release Scope

- `v0.1.0` is a source milestone and tagged development build.
- The application is universal (`arm64` and `x86_64`) and ad-hoc signed.
- The ZIP and SHA-256 checksum are retained by GitHub Actions for 90 days.
- Apple Developer Program access and App Store access are not required.
- The artifact is not a public, notarized macOS release.

## Prerequisites

- A compatible Xcode toolchain.
- Apache 2.0 `LICENSE` and `NOTICE` files committed.
- The version in `VERSION` matches `docs/releases/<version>.md`.
- The full automated suite passes.
- The release commit is pushed to `main`.

Complete the manual checklist before sharing an artifact outside the repository
maintainers.

## Local Candidate

Build and verify the same ad-hoc artifact locally:

```sh
scripts/release.sh
```

The command runs the complete test suite and creates:

```text
dist/release/BetterTot-<version>.zip
dist/release/BetterTot-<version>.sha256
```

Verify an existing artifact independently:

```sh
scripts/verify-release.sh \
  --version "$(tr -d '[:space:]' < VERSION)" \
  --directory dist/release
```

## Create the Tag

1. Confirm `main` is clean and synchronized with `origin/main`.
2. Run `scripts/release.sh`.
3. Create an annotated tag matching `VERSION`.
4. Push the tag.

```sh
version="$(tr -d '[:space:]' < VERSION)"
git tag -a "v$version" -m "BetterTot $version"
git push origin "v$version"
```

The `Tagged Build` workflow rejects a mismatched version, missing legal files,
missing release notes, or a tag outside `main` history. It then runs the full
suite, builds and verifies the ad-hoc ZIP, and uploads these files:

```text
BetterTot-<version>.zip
BetterTot-<version>.sha256
release-notes.md
TAGGED-BUILD-NOTICE.txt
```

The workflow has read-only repository permissions and receives no Apple
credentials. It intentionally does not create a GitHub Release.

## Installation

Download the tagged artifact from its GitHub Actions run, verify the checksum,
extract it, and move `BetterTot.app` to `/Applications`:

```sh
shasum -a 256 -c BetterTot-<version>.sha256
```

The bundled checksum detects transfer or storage corruption. Artifact
authenticity depends on downloading it from the expected tagged workflow run;
the ad-hoc signature does not establish a developer identity.

Because the app is ad-hoc signed and unnotarized, macOS may require an explicit
local approval through Privacy & Security settings. Never disable Gatekeeper
globally.

To upgrade, quit BetterTot and replace the application in `/Applications`.
Pads remain under `~/Library/Application Support/BetterTot/` and are not part
of the application bundle.

## Uninstall

Quit BetterTot and move the app to Trash. To remove all user data too,
separately delete:

```text
~/Library/Application Support/BetterTot/
~/Library/Preferences/org.bettertot.BetterTot.plist
```

Deleting Application Support permanently removes pads, journals, and backups.

## Future Public Distribution

Developer ID signing, Apple notarization, a public GitHub Release, clean-Mac
acceptance, and Homebrew publishing require a separate explicit release
decision. Add those controls as a protected workflow rather than expanding the
current ad-hoc tag job.
