# BetterTot Local Build Runbook

BetterTot's current distribution target is a private/local universal macOS
application with an ad-hoc signature and SHA-256 checksum. It is not being
published, so Developer ID signing, Apple notarization, and App Store access are
not required.

## Current Release Status

- Repository-controlled Phase 4 work is complete.
- The ad-hoc app and ZIP are the final artifacts for the private/local scope.
- Apple Developer Program authorization and notarization are not release
  blockers.
- CI may produce explicitly labeled ad-hoc development previews for testing.
- Do not create a public `v0.1.0` release from these artifacts.

## Local Prerequisites

- A standalone Git repository whose root is the BetterTot directory.
- A compatible Xcode toolchain.
- The Apache 2.0 `LICENSE` and project `NOTICE` committed.
- The 80% coverage target met and the README manual checklist signed off.

## Local Artifact

Build an ad-hoc-signed artifact for local verification:

```sh
scripts/release.sh
```

This runs the test suite and creates:

```text
dist/release/BetterTot-<version>.zip
dist/release/BetterTot-<version>.sha256
```

Ad-hoc signing is sufficient for the current private/local scope. It is not an
identified-developer signature and the artifact must not be represented as a
public macOS release.

## CI Development Preview

The `CI` workflow can upload the same verified ad-hoc ZIP as a development
preview. Run the workflow manually against `main`, then download
`BetterTot-preview-<commit>`. Ordinary push and pull-request runs do not upload
preview artifacts.

The artifact contains:

```text
BetterTot-<version>-preview.<run>.zip
BetterTot-<version>-preview.<run>.sha256
PREVIEW-NOTICE.txt
```

Preview artifacts are retained for 14 days. They are for trusted development
testing only, may require an explicit local Gatekeeper override, and must not be
published as GitHub Releases or used by the Homebrew Cask. Never disable
Gatekeeper globally to test a preview. The preview run number is also embedded
as the bundle build number for traceability.

## Optional Future Public Distribution

The remaining Developer ID, notarization, GitHub Release, clean-Mac, and
Homebrew instructions are intentionally inactive. Use them only after an
explicit decision to distribute BetterTot to other users.

## Optional Developer ID Release

The protected GitHub workflow is the preferred signing path. For an exceptional
local release, use a disposable Keychain rather than importing release
credentials into the login Keychain:

```sh
BETTERTOT_RELEASE_TMP="$(mktemp -d "${TMPDIR:-/tmp}/bettertot-release.XXXXXX")"
BETTERTOT_RELEASE_KEYCHAIN="$BETTERTOT_RELEASE_TMP/signing.keychain-db"
read -r -s BETTERTOT_KEYCHAIN_PASSWORD
read -r -s BETTERTOT_CERTIFICATE_PASSWORD
cleanup_release_credentials() {
  security delete-keychain "$BETTERTOT_RELEASE_KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$BETTERTOT_RELEASE_TMP"
  unset BETTERTOT_KEYCHAIN_PASSWORD BETTERTOT_CERTIFICATE_PASSWORD
}
trap cleanup_release_credentials EXIT

security create-keychain -p "$BETTERTOT_KEYCHAIN_PASSWORD" "$BETTERTOT_RELEASE_KEYCHAIN"
security unlock-keychain -p "$BETTERTOT_KEYCHAIN_PASSWORD" "$BETTERTOT_RELEASE_KEYCHAIN"
security import /path/to/DeveloperID.p12 \
  -k "$BETTERTOT_RELEASE_KEYCHAIN" \
  -P "$BETTERTOT_CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign
security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s \
  -k "$BETTERTOT_KEYCHAIN_PASSWORD" \
  "$BETTERTOT_RELEASE_KEYCHAIN"

xcrun notarytool store-credentials BetterTot \
  --keychain "$BETTERTOT_RELEASE_KEYCHAIN" \
  --key /path/to/AuthKey_KEYID.p8 \
  --key-id KEYID \
  --issuer ISSUER_UUID

scripts/release.sh \
  --sign-identity "Developer ID Application: Team Name (TEAMID)" \
  --notary-profile BetterTot \
  --notary-keychain "$BETTERTOT_RELEASE_KEYCHAIN" \
  --repository OWNER/BetterTot
```

Delete the disposable Keychain and temporary directory even when a release
fails. Do not commit, log, or place certificate/API-key contents directly in a
command line.

The script performs these operations in order:

1. Runs Swift and release-tooling tests.
2. Builds a universal `arm64` and `x86_64` executable.
3. Signs the application with Hardened Runtime and a secure timestamp.
4. Creates the release ZIP.
5. Submits the ZIP with `notarytool` and waits for acceptance.
6. Staples and validates the ticket.
7. Recreates the ZIP around the stapled application.
8. Verifies Gatekeeper acceptance and the application signature.
9. Writes a SHA-256 checksum and a matching Homebrew Cask proposal.

## Optional GitHub Configuration

Configure these secrets on the protected `release` environment:

| Secret | Value |
|---|---|
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded Developer ID `.p12` |
| `APPLE_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_SIGNING_IDENTITY` | Full Developer ID Application identity |
| `APPLE_API_KEY_BASE64` | Base64-encoded App Store Connect `.p8` key |
| `APPLE_API_KEY_ID` | App Store Connect API key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect issuer UUID |
| `KEYCHAIN_PASSWORD` | Random password used only for the temporary CI Keychain |

Send encoded files directly to GitHub through standard input so credentials do
not enter shell history or the system clipboard:

```sh
base64 -i DeveloperID.p12 | \
  gh secret set APPLE_CERTIFICATE_BASE64 --env release --repo OWNER/BetterTot
base64 -i AuthKey_KEYID.p8 | \
  gh secret set APPLE_API_KEY_BASE64 --env release --repo OWNER/BetterTot
```

Configure a repository ruleset that protects `main`, requires review before
merge, and restricts creation or modification of `v*` tags. Configure at least
one required reviewer on the `release` environment.

The release workflow tests and builds the unsigned application in an
unprivileged job where release secrets are unavailable. A protected signing job
with read-only repository permissions imports secrets into a temporary
Keychain, signs and notarizes the prebuilt bundle, and deletes the Keychain and
decoded files when the step exits. A final job receives only signed assets and
holds GitHub release and attestation permissions; it has no Apple credentials.

## Optional Version and Tag

1. Update `VERSION` using `MAJOR.MINOR.PATCH` format.
2. Update release notes and run `scripts/test.sh`.
3. Commit the release changes.
4. Create the matching annotated tag, such as `v0.1.0`.
5. Push the commit and tag.

The release workflow rejects a tag that does not match `VERSION` or point to a
commit in `main` history. It then builds without credentials, signs and
notarizes in the protected environment, verifies and attests the artifacts, and
creates a draft GitHub release. Publish the draft only after the clean-Mac
acceptance checks pass.

## Optional Clean-Mac Acceptance

Before announcing a release:

1. Download the ZIP from GitHub rather than using the local build.
2. Verify `shasum -a 256 -c BetterTot-<version>.sha256`.
3. Extract and open BetterTot on a supported Mac without Xcode installed.
4. Confirm Gatekeeper opens it without an override.
5. Confirm the menu-bar item, global shortcut, editor, and launch-at-login work.
6. Upgrade over a copy with populated pads and confirm all text remains intact.
7. Run the manual checklist in `README.md`, including VoiceOver and IME checks.

### 0.1.0 Acceptance Record

- 2026-07-27: Local ad-hoc candidate passed the README manual functional
  checklist, as reported by the tester.
- Not required for the current private/local scope. Repeat the checklist with a
  notarized draft on a clean supported Mac only if public distribution resumes.

Command-line verification should report `source=Notarized Developer ID`:

```sh
spctl --assess --type execute --verbose=2 BetterTot.app
codesign --verify --deep --strict --verbose=2 BetterTot.app
xcrun stapler validate BetterTot.app
```

## Install, Upgrade, and Uninstall

Install by moving `BetterTot.app` to `/Applications` and launching it once.

Upgrade by quitting BetterTot and replacing the application in `/Applications`.
User pads remain under `~/Library/Application Support/BetterTot/` and are not
part of the application bundle.

Uninstall by quitting BetterTot and moving the app to Trash. To remove all user
data too, separately delete:

```text
~/Library/Application Support/BetterTot/
~/Library/Preferences/org.bettertot.BetterTot.plist
```

Deleting the Application Support directory permanently removes pads, journals,
and backups. Preserve or export it before destructive removal.

## Optional Homebrew Cask

Each release generates `dist/release/bettertot.rb`. Test it against the public
release URL before proposing it to Homebrew. The Cask intentionally does not
delete user pads during ordinary uninstall.

## Official References

- [Distributing software with Developer ID](https://developer.apple.com/developer-id/)
- [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)
- [Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [GitHub Actions security](https://docs.github.com/en/actions/reference/security/secure-use)
- [GitHub artifact attestations](https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations)
