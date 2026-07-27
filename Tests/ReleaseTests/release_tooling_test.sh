#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bettertot-release-tests.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    [[ "$haystack" == *"$needle"* ]] || fail "$message"
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="$3"
    [[ "$haystack" != *"$needle"* ]] || fail "$message"
}

assert_fails() {
    local message="$1"
    shift
    if "$@" >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"; then
        fail "$message"
    fi
}

[[ -x "$ROOT/scripts/release.sh" ]] || fail "scripts/release.sh must be executable"
[[ -x "$ROOT/scripts/generate-info-plist.sh" ]] || fail "plist generator must be executable"
[[ -x "$ROOT/scripts/generate-app-icon.sh" ]] || fail "app icon generator must be executable"
[[ -x "$ROOT/scripts/render-cask.sh" ]] || fail "Cask renderer must be executable"
[[ -f "$ROOT/Assets/AppIcon.svg" ]] || fail "app icon SVG master must be present"
[[ -f "$ROOT/LICENSE" ]] || fail "Apache 2.0 LICENSE must be present"
[[ -f "$ROOT/NOTICE" ]] || fail "Apache NOTICE must be present"
assert_contains "$(cat "$ROOT/LICENSE")" "Apache License" \
    "LICENSE must contain the Apache license"
assert_contains "$(cat "$ROOT/LICENSE")" "Version 2.0, January 2004" \
    "LICENSE must contain Apache License 2.0"

help_output="$("$ROOT/scripts/release.sh" --help)"
assert_contains "$help_output" "--version" "release help must document --version"
assert_contains "$help_output" "--dry-run" "release help must document --dry-run"

assert_fails "invalid semantic versions must be rejected" \
    "$ROOT/scripts/release.sh" --version 1.2 --dry-run
assert_contains "$(cat "$TMP_DIR/stderr")" "semantic version" \
    "invalid version error must be actionable"

assert_fails "non-numeric build numbers must be rejected" \
    "$ROOT/scripts/release.sh" --version 1.2.3 --build-number abc --dry-run
assert_contains "$(cat "$TMP_DIR/stderr")" "build number" \
    "invalid build-number error must be actionable"

assert_fails "a missing notarization Keychain must be rejected" \
    "$ROOT/scripts/release.sh" \
    --version 1.2.3 \
    --sign-identity "Developer ID Application: Example (TEAMID)" \
    --notary-profile BetterTotTest \
    --notary-keychain "$TMP_DIR/missing.keychain-db" \
    --dry-run
assert_contains "$(cat "$TMP_DIR/stderr")" "notary keychain" \
    "missing notarization Keychain error must be actionable"

dry_run_output="$("$ROOT/scripts/release.sh" \
    --version 1.2.3 \
    --build-number 42 \
    --dry-run)"
assert_contains "$dry_run_output" "BetterTot-1.2.3.zip" \
    "dry run must show the versioned ZIP artifact"
assert_contains "$dry_run_output" "BetterTot-1.2.3.sha256" \
    "dry run must show the checksum artifact"

plist="$TMP_DIR/Info.plist"
"$ROOT/scripts/generate-info-plist.sh" \
    --version 1.2.3 \
    --build-number 42 \
    --output "$plist"
plutil -lint "$plist" >/dev/null
[[ "$(plutil -extract CFBundleShortVersionString raw "$plist")" == "1.2.3" ]] || \
    fail "plist must contain the requested marketing version"
[[ "$(plutil -extract CFBundleVersion raw "$plist")" == "42" ]] || \
    fail "plist must contain the requested build number"
[[ "$(plutil -extract LSMinimumSystemVersion raw "$plist")" == "13.0" ]] || \
    fail "plist must preserve the package minimum macOS version"
[[ "$(plutil -extract CFBundleIconFile raw "$plist")" == "BetterTot.icns" ]] || \
    fail "plist must declare the bundled app icon"

icon_one="$TMP_DIR/BetterTot-one.icns"
icon_two="$TMP_DIR/BetterTot-two.icns"
"$ROOT/scripts/generate-app-icon.sh" --output "$icon_one"
"$ROOT/scripts/generate-app-icon.sh" --output "$icon_two"
cmp -s "$icon_one" "$icon_two" || fail "app icon generation must be deterministic"
[[ -s "$icon_one" ]] || fail "app icon generator must produce a non-empty ICNS"

extracted_iconset="$TMP_DIR/Extracted.iconset"
iconutil --convert iconset --output "$extracted_iconset" "$icon_one"
[[ -f "$extracted_iconset/icon_16x16.png" ]] || \
    fail "app icon must contain a 16x16 representation"
[[ -f "$extracted_iconset/icon_512x512@2x.png" ]] || \
    fail "app icon must contain a 1024x1024 representation"
[[ "$(sips --getProperty pixelWidth "$extracted_iconset/icon_512x512@2x.png" 2>/dev/null | awk '/pixelWidth/ { print $2 }')" == "1024" ]] || \
    fail "largest app icon representation must be 1024 pixels wide"

app="$TMP_DIR/BetterTot.app"
"$ROOT/scripts/bundle.sh" \
    --version 1.2.3 \
    --build-number 42 \
    --output "$app" >/dev/null
[[ -s "$app/Contents/Resources/BetterTot.icns" ]] || \
    fail "application bundle must contain BetterTot.icns"
cmp -s "$icon_one" "$app/Contents/Resources/BetterTot.icns" || \
    fail "application bundle must contain the generated app icon"
[[ "$(plutil -extract CFBundleIconFile raw "$app/Contents/Info.plist")" == "BetterTot.icns" ]] || \
    fail "bundled plist must reference BetterTot.icns"

release_zip="$TMP_DIR/BetterTot-1.2.3.zip"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$release_zip"
assert_contains "$(unzip -Z1 "$release_zip")" \
    "BetterTot.app/Contents/Resources/BetterTot.icns" \
    "release ZIP must contain the bundled app icon"
if unzip -Z1 "$release_zip" | grep -E '(^|/)\._' >/dev/null; then
    fail "release ZIP must not contain AppleDouble metadata files"
fi

sha="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
cask_output="$("$ROOT/scripts/render-cask.sh" \
    --version 1.2.3 \
    --sha256 "$sha" \
    --repository example/BetterTot)"
assert_contains "$cask_output" 'version "1.2.3"' "Cask must contain the version"
assert_contains "$cask_output" "sha256 \"$sha\"" "Cask must contain the checksum"
assert_contains "$cask_output" \
    'url "https://github.com/example/BetterTot/releases/download/v#{version}/BetterTot-#{version}.zip"' \
    "Cask URL must target the matching GitHub release"
assert_contains "$cask_output" 'uninstall quit: "org.bettertot.BetterTot"' \
    "Cask must stop BetterTot before uninstalling"

printf -v placeholder_sha '%064d' 0
cask_template="$("$ROOT/scripts/render-cask.sh" \
    --version 1.2.3 \
    --sha256 "$placeholder_sha" \
    --repository example/BetterTot)"
cask_from_template="$(printf '%s\n' "$cask_template" | sed "s/$placeholder_sha/$sha/")"
[[ "$cask_from_template" == "$cask_output" ]] || \
    fail "release-time checksum substitution must match direct Cask rendering"

assert_fails "Cask renderer must reject malformed repositories" \
    "$ROOT/scripts/render-cask.sh" \
    --version 1.2.3 \
    --sha256 "$sha" \
    --repository invalid

release_workflow="$(cat "$ROOT/.github/workflows/release.yml")"
release_script="$(cat "$ROOT/scripts/release.sh")"
assert_contains "$release_script" '--norsrc --noextattr' \
    "local release archives must omit resource forks and extended attributes"
assert_contains "$release_workflow" '--norsrc --noextattr' \
    "CI release archives must omit resource forks and extended attributes"
assert_contains "$release_workflow" '"v*.*.*"' \
    "release workflow must use a GitHub-compatible tag glob"
assert_contains "$release_workflow" '--draft' \
    "release workflow must leave clean-install candidates as drafts"
assert_contains "$release_workflow" \
    'git merge-base --is-ancestor "$GITHUB_SHA" "origin/main"' \
    "release workflow must reject tags outside main history"
assert_contains "$release_workflow" 'needs: build' \
    "credentialed release job must consume an unprivileged build job"
assert_contains "$release_workflow" 'needs: sign' \
    "publishing must consume the credentialed signing job"
assert_contains "$release_workflow" 'BetterTot-signed-${{ github.sha }}' \
    "signing and publishing must exchange only signed artifacts"
assert_contains "$release_workflow" 'unexpected_entries=' \
    "signing must reject files outside the BetterTot.app archive root"
assert_contains "$release_workflow" 'mktemp -d "$RUNNER_TEMP/bettertot-unsigned.XXXXXX"' \
    "signing must extract into a fresh temporary directory"
assert_contains "$release_workflow" 'needs.sign.outputs.version' \
    "publishing must address exact versioned assets"
assert_contains "$release_workflow" 'scripts/render-cask.sh' \
    "production Cask must come from the tested renderer"
assert_contains "$release_workflow" '[[ -f LICENSE && -f NOTICE ]]' \
    "release workflow must require Apache legal files"
secret_section="${release_workflow#*APPLE_CERTIFICATE_BASE64}"
assert_not_contains "$secret_section" 'scripts/' \
    "secret-bearing workflow steps must not execute repository scripts"
sign_section="${release_workflow#*  sign:}"
sign_section="${sign_section%%  publish:*}"
assert_not_contains "$sign_section" 'contents: write' \
    "Apple credential job must not have repository write permission"
assert_not_contains "$sign_section" 'id-token: write' \
    "Apple credential job must not have OIDC permission"
assert_not_contains "$sign_section" 'attestations: write' \
    "Apple credential job must not have attestation permission"
publish_section="${release_workflow#*  publish:}"
assert_not_contains "$publish_section" 'APPLE_CERTIFICATE' \
    "publishing job must not receive the signing certificate"
assert_not_contains "$publish_section" 'APPLE_API_KEY' \
    "publishing job must not receive notarization credentials"

printf 'Release tooling tests passed\n'
