# BetterTot Release Runbook

BetterTot ships as an ad-hoc-signed macOS application in a ZIP and an unsigned
installer package. Tagged builds are stored as repository-scoped GitHub
Actions artifacts. A maintainer may also publish the locally verified files to
GitHub Releases. The automated workflow does not use Apple credentials,
notarize either artifact, create a GitHub Release, or publish a Homebrew Cask.

## Release Scope

- Releases remain development builds until Developer ID signing and
  notarization are available.
- The application is universal (`arm64` and `x86_64`) and ad-hoc signed.
- The ZIP, installer package, and SHA-256 checksum are retained by GitHub
  Actions for 90 days.
- Apple Developer Program access and App Store access are not required.
- Public GitHub Release assets are not notarized macOS distributions.

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
dist/release/BetterTot-<version>.pkg
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
suite, builds and verifies the ZIP and installer, and uploads these files:

```text
BetterTot-<version>.zip
BetterTot-<version>.pkg
BetterTot-<version>.sha256
release-notes.md
TAGGED-BUILD-NOTICE.txt
```

The workflow has read-only repository permissions and receives no Apple
credentials. It intentionally does not create a GitHub Release.

## Publish the GitHub Release

After the annotated tag is pushed and the tagged workflow succeeds, publish
the same locally verified ZIP, installer, and checksum with the curated notes:

```sh
version="$(tr -d '[:space:]' < VERSION)"
gh release create "v$version" \
  "dist/release/BetterTot-$version.zip" \
  "dist/release/BetterTot-$version.pkg" \
  "dist/release/BetterTot-$version.sha256" \
  --title "BetterTot $version" \
  --notes-file "docs/releases/$version.md" \
  --verify-tag
```

Do not publish artifacts built from a different commit than the release tag.
Keep the ad-hoc signing and notarization limitations visible in the release
notes.

## Installation

Download the assets from the GitHub Release or the tagged artifact from its
GitHub Actions run and verify both distributables:

```sh
shasum -a 256 -c BetterTot-<version>.sha256
```

Open `BetterTot-<version>.pkg` for the standard Installer flow, or extract the
ZIP and move `BetterTot.app` to `/Applications` manually. Both install the same
verified application bundle.

The bundled checksum detects transfer or storage corruption. Artifact
authenticity depends on downloading it from the expected tagged workflow run;
the ad-hoc signature does not establish a developer identity.

Because the app is ad-hoc signed and the installer is unsigned, with neither
artifact notarized, macOS may require an explicit local approval through
Privacy & Security settings. Never disable Gatekeeper globally.

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

Developer ID signing, Apple notarization, clean-Mac Gatekeeper acceptance, and
Homebrew publishing require a separate explicit release decision. Add those
controls as a protected workflow rather than expanding the current ad-hoc tag
job.
