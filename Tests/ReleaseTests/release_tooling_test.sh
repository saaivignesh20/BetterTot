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
[[ -x "$ROOT/scripts/package-installer.sh" ]] || \
    fail "scripts/package-installer.sh must be executable"
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
assert_contains "$help_output" ".pkg" "release help must document the installer artifact"

installer_help="$("$ROOT/scripts/package-installer.sh" --help)"
assert_contains "$installer_help" "--application" \
    "installer help must document the source application"
assert_contains "$installer_help" "--output" \
    "installer help must document the package output"

assert_fails "invalid semantic versions must be rejected" \
    "$ROOT/scripts/release.sh" --version 1.2 --dry-run
assert_contains "$(cat "$TMP_DIR/stderr")" "semantic version" \
    "invalid version error must be actionable"
assert_fails "installer must reject invalid semantic versions" \
    "$ROOT/scripts/package-installer.sh" \
    --version 1.2 \
    --application "$TMP_DIR/missing.app" \
    --output "$TMP_DIR/invalid.pkg"
assert_contains "$(cat "$TMP_DIR/stderr")" "semantic version" \
    "invalid installer version error must be actionable"

assert_fails "non-numeric build numbers must be rejected" \
    "$ROOT/scripts/release.sh" --version 1.2.3 --build-number abc --dry-run
assert_contains "$(cat "$TMP_DIR/stderr")" "build number" \
    "invalid build-number error must be actionable"

dry_run_output="$("$ROOT/scripts/release.sh" \
    --version 1.2.3 \
    --build-number 42 \
    --dry-run)"
assert_contains "$dry_run_output" "BetterTot-1.2.3.zip" \
    "dry run must show the versioned ZIP artifact"
assert_contains "$dry_run_output" "BetterTot-1.2.3.pkg" \
    "dry run must show the versioned installer artifact"
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
[[ -s "$app/Contents/Resources/MenuBarIcon.png" ]] || \
    fail "application bundle must contain MenuBarIcon.png"
cmp -s "$icon_one" "$app/Contents/Resources/BetterTot.icns" || \
    fail "application bundle must contain the generated app icon"
cmp -s "$ROOT/Assets/MenuBarIcon.png" "$app/Contents/Resources/MenuBarIcon.png" || \
    fail "application bundle must contain the selected menu-bar icon"
[[ "$(plutil -extract CFBundleIconFile raw "$app/Contents/Info.plist")" == "BetterTot.icns" ]] || \
    fail "bundled plist must reference BetterTot.icns"

release_zip="$TMP_DIR/BetterTot-1.2.3.zip"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$release_zip"
assert_contains "$(unzip -Z1 "$release_zip")" \
    "BetterTot.app/Contents/Resources/BetterTot.icns" \
    "release ZIP must contain the bundled app icon"
assert_contains "$(unzip -Z1 "$release_zip")" \
    "BetterTot.app/Contents/Resources/MenuBarIcon.png" \
    "release ZIP must contain the menu-bar icon"
if unzip -Z1 "$release_zip" | grep -E '(^|/)\._' >/dev/null; then
    fail "release ZIP must not contain AppleDouble metadata files"
fi

installer_pkg="$TMP_DIR/BetterTot-1.2.3.pkg"
"$ROOT/scripts/package-installer.sh" \
    --version 1.2.3 \
    --application "$app" \
    --output "$installer_pkg"
[[ -s "$installer_pkg" ]] || fail "installer builder must produce a non-empty package"
installer_payload="$(pkgutil --payload-files "$installer_pkg")"
assert_contains "$installer_payload" "./BetterTot.app/Contents/MacOS/BetterTot" \
    "installer payload must contain the BetterTot executable"
if grep -E '(^|/)\._|(^|/)\.__' <<< "$installer_payload" >/dev/null; then
    fail "installer payload must not contain AppleDouble metadata files"
fi
installer_expanded="$TMP_DIR/installer-expanded"
pkgutil --expand-full "$installer_pkg" "$installer_expanded"
[[ ! -e "$installer_expanded/Scripts" ]] || \
    fail "installer must not contain privileged scripts"
package_info="$installer_expanded/PackageInfo"
[[ "$(xmllint --xpath 'string(/pkg-info/@identifier)' "$package_info")" == \
    "org.bettertot.BetterTot.pkg" ]] || fail "installer identifier must be stable"
[[ "$(xmllint --xpath 'string(/pkg-info/@version)' "$package_info")" == "1.2.3" ]] || \
    fail "installer version must match the release version"
[[ "$(xmllint --xpath 'string(/pkg-info/@install-location)' "$package_info")" == \
    "/Applications" ]] || fail "installer must target /Applications"
cmp -s \
    "$app/Contents/MacOS/BetterTot" \
    "$installer_expanded/Payload/BetterTot.app/Contents/MacOS/BetterTot" || \
    fail "installer executable must match the release application"
codesign --verify --deep --strict --verbose=2 \
    "$installer_expanded/Payload/BetterTot.app"

polluted_dir="$TMP_DIR/polluted"
mkdir -p "$polluted_dir"
cp "$release_zip" "$polluted_dir/BetterTot-1.2.3.zip"
cp "$installer_pkg" "$polluted_dir/BetterTot-1.2.3.pkg"
printf 'unexpected payload\n' > "$TMP_DIR/unexpected.txt"
(
    cd "$TMP_DIR"
    zip -q "$polluted_dir/BetterTot-1.2.3.zip" unexpected.txt
    cd "$polluted_dir"
    shasum -a 256 \
        BetterTot-1.2.3.zip \
        BetterTot-1.2.3.pkg \
        > BetterTot-1.2.3.sha256
)
assert_fails "release verification must reject unexpected top-level entries" \
    "$ROOT/scripts/verify-release.sh" \
    --version 1.2.3 \
    --directory "$polluted_dir"
assert_contains "$(cat "$TMP_DIR/stderr")" "unexpected archive entry" \
    "unexpected archive entries must produce an actionable error"

unchecked_dir="$TMP_DIR/unchecked-installer"
mkdir -p "$unchecked_dir"
cp "$release_zip" "$unchecked_dir/BetterTot-1.2.3.zip"
cp "$installer_pkg" "$unchecked_dir/BetterTot-1.2.3.pkg"
(
    cd "$unchecked_dir"
    shasum -a 256 BetterTot-1.2.3.zip > BetterTot-1.2.3.sha256
)
assert_fails "release verification must require a checksum for the installer" \
    "$ROOT/scripts/verify-release.sh" \
    --version 1.2.3 \
    --directory "$unchecked_dir"
assert_contains "$(cat "$TMP_DIR/stderr")" "checksum must cover exactly" \
    "missing installer checksums must produce an actionable error"

tampered_dir="$TMP_DIR/tampered-installer"
mkdir -p "$tampered_dir"
cp "$release_zip" "$tampered_dir/BetterTot-1.2.3.zip"
pkgutil --expand "$installer_pkg" "$tampered_dir/expanded"
sed 's/version="1.2.3"/version="9.9.9"/' \
    "$tampered_dir/expanded/PackageInfo" \
    > "$tampered_dir/expanded/PackageInfo.changed"
mv \
    "$tampered_dir/expanded/PackageInfo.changed" \
    "$tampered_dir/expanded/PackageInfo"
pkgutil --flatten \
    "$tampered_dir/expanded" \
    "$tampered_dir/BetterTot-1.2.3.pkg"
(
    cd "$tampered_dir"
    shasum -a 256 \
        BetterTot-1.2.3.zip \
        BetterTot-1.2.3.pkg \
        > BetterTot-1.2.3.sha256
)
assert_fails "release verification must reject mismatched installer metadata" \
    "$ROOT/scripts/verify-release.sh" \
    --version 1.2.3 \
    --directory "$tampered_dir"
assert_contains "$(cat "$TMP_DIR/stderr")" "installer version" \
    "tampered installer versions must produce an actionable error"

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
ci_workflow="$(cat "$ROOT/.github/workflows/ci.yml")"
release_script="$(cat "$ROOT/scripts/release.sh")"
verify_script="$(cat "$ROOT/scripts/verify-release.sh")"
assert_contains "$release_script" '--norsrc --noextattr' \
    "local release archives must omit resource forks and extended attributes"
assert_contains "$release_script" 'scripts/package-installer.sh' \
    "local releases must build the tested installer package"
assert_contains "$release_script" 'REPOSITORY=""' \
    "Homebrew rendering must require an explicit repository option"
assert_not_contains "$release_script" 'REPOSITORY="${GITHUB_REPOSITORY' \
    "GitHub's ambient repository variable must not enable Homebrew rendering"
assert_contains "$verify_script" 'PKG_EXPANDED/Scripts' \
    "release verification must reject privileged installer scripts"
assert_contains "$release_workflow" '"v*.*.*"' \
    "release workflow must use a GitHub-compatible tag glob"
assert_contains "$release_workflow" \
    'git merge-base --is-ancestor "$GITHUB_SHA" "origin/main"' \
    "release workflow must reject tags outside main history"
assert_contains "$release_workflow" 'persist-credentials: false' \
    "tagged source must not retain checkout credentials while repository scripts run"
assert_contains "$release_workflow" \
    'git cat-file -t "$GITHUB_REF_NAME"' \
    "release workflow must require an annotated tag"
assert_contains "$release_workflow" '[[ -f LICENSE && -f NOTICE ]]' \
    "release workflow must require Apache legal files"
assert_contains "$release_workflow" 'scripts/release.sh' \
    "tagged builds must use the tested release script"
assert_contains "$release_workflow" '--sign-identity -' \
    "tagged builds must use an ad-hoc signature"
assert_contains "$release_workflow" 'TAGGED-BUILD-NOTICE.txt' \
    "tagged artifacts must include an unnotarized-build warning"
assert_contains "$release_workflow" '"dist/release/BetterTot-$VERSION.pkg"' \
    "tagged artifacts must include the macOS installer package"
assert_contains "$release_workflow" 'actions/upload-artifact' \
    "tagged builds must remain repository-scoped workflow artifacts"
assert_not_contains "$release_workflow" 'APPLE_CERTIFICATE' \
    "tagged builds must not receive Apple signing certificates"
assert_not_contains "$release_workflow" 'APPLE_API_KEY' \
    "tagged builds must not receive Apple notarization credentials"
assert_not_contains "$release_workflow" 'notarytool' \
    "tagged builds must not attempt notarization"
assert_not_contains "$release_workflow" 'gh release create' \
    "tagged builds must not create a public GitHub Release"
assert_not_contains "$release_workflow" 'contents: write' \
    "tagged builds must not receive repository write permission"
assert_not_contains "$release_workflow" 'id-token: write' \
    "tagged builds must not receive OIDC permission"
assert_not_contains "$release_workflow" 'attestations: write' \
    "tagged builds must not receive attestation permission"
assert_contains "$ci_workflow" 'workflow_dispatch:' \
    "CI must support manually requested preview builds"
assert_contains "$ci_workflow" 'BetterTot-preview-${{ github.sha }}' \
    "CI preview artifacts must be clearly labeled by source commit"
assert_contains "$ci_workflow" 'PREVIEW-NOTICE.txt' \
    "CI preview artifacts must include an unnotarized-build warning"
assert_contains "$ci_workflow" "github.event_name == 'workflow_dispatch'" \
    "CI previews must only be uploaded after a manual request"
assert_contains "$ci_workflow" '--build-number "$GITHUB_RUN_NUMBER"' \
    "CI previews must identify their workflow run in bundle metadata"
assert_contains "$ci_workflow" 'BetterTot-$version-preview.$GITHUB_RUN_NUMBER.zip' \
    "CI preview ZIPs must be distinguishable from production release assets"
assert_contains "$ci_workflow" 'BetterTot-*-preview.*.sha256' \
    "CI preview artifacts must include a distinctly named checksum"
assert_contains "$ci_workflow" 'ad-hoc signed and has not been notarized by Apple' \
    "CI preview warnings must state the signing and notarization limitations"
assert_not_contains "$ci_workflow" 'contents: write' \
    "CI preview builds must not receive repository write permission"

printf 'Release tooling tests passed\n'
