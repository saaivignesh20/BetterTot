#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bettertot-local-install-tests.XXXXXX")"
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

assert_fails() {
    local message="$1"
    shift
    if "$@" >"$TMP_DIR/stdout" 2>"$TMP_DIR/stderr"; then
        fail "$message"
    fi
}

make_app() {
    local path="$1"
    local identifier="$2"
    local marker="$3"
    mkdir -p "$path/Contents/MacOS" "$path/Contents/Resources"
    printf '#!/bin/sh\nexit 0\n' > "$path/Contents/MacOS/BetterTot"
    chmod +x "$path/Contents/MacOS/BetterTot"
    printf '%s\n' "$marker" > "$path/Contents/Resources/marker.txt"
    plutil -create xml1 "$path/Contents/Info.plist"
    plutil -insert CFBundleIdentifier -string "$identifier" "$path/Contents/Info.plist"
    plutil -insert CFBundleExecutable -string BetterTot "$path/Contents/Info.plist"
    plutil -insert CFBundleShortVersionString -string 9.8.7 "$path/Contents/Info.plist"
    plutil -insert CFBundleVersion -string 42 "$path/Contents/Info.plist"
    codesign --force --sign - "$path" >/dev/null
}

[[ -x "$ROOT/scripts/install-local.sh" ]] || \
    fail "scripts/install-local.sh must be executable"
[[ -x "$ROOT/scripts/build-and-install.sh" ]] || \
    fail "scripts/build-and-install.sh must be executable"

install_help="$("$ROOT/scripts/install-local.sh" --help)"
assert_contains "$install_help" "--application" \
    "local installer help must document the source application"
assert_contains "$install_help" "--destination" \
    "local installer help must document the destination"
assert_contains "$install_help" "--no-relaunch" \
    "local installer help must document non-interactive installation"

build_help="$("$ROOT/scripts/build-and-install.sh" --help)"
assert_contains "$build_help" ".pkg" \
    "build-and-install help must document package creation"
assert_contains "$build_help" "/Applications/BetterTot.app" \
    "build-and-install help must document the default installation"

dry_run="$("$ROOT/scripts/build-and-install.sh" \
    --version 1.2.3 \
    --build-number 42 \
    --destination "$TMP_DIR/Applications/BetterTot.app" \
    --dry-run)"
assert_contains "$dry_run" "BetterTot-1.2.3.pkg" \
    "dry run must identify the package artifact"
assert_contains "$dry_run" "$TMP_DIR/Applications/BetterTot.app" \
    "dry run must identify the installation destination"

source_app="$TMP_DIR/source/BetterTot.app"
destination="$TMP_DIR/Applications/BetterTot.app"
mkdir -p "$(dirname "$destination")"
make_app "$source_app" org.bettertot.BetterTot first

"$ROOT/scripts/install-local.sh" \
    --application "$source_app" \
    --destination "$destination" \
    --no-relaunch >/dev/null
[[ "$(cat "$destination/Contents/Resources/marker.txt")" == "first" ]] || \
    fail "local installation must copy the requested application"
codesign --verify --deep --strict "$destination"

replacement_app="$TMP_DIR/replacement/BetterTot.app"
make_app "$replacement_app" org.bettertot.BetterTot replacement
"$ROOT/scripts/install-local.sh" \
    --application "$replacement_app" \
    --destination "$destination" \
    --no-relaunch >/dev/null
[[ "$(cat "$destination/Contents/Resources/marker.txt")" == "replacement" ]] || \
    fail "local installation must replace an existing BetterTot bundle"

foreign_app="$TMP_DIR/foreign/BetterTot.app"
make_app "$foreign_app" com.example.ForeignApp foreign
assert_fails "local installation must reject a foreign bundle identifier" \
    "$ROOT/scripts/install-local.sh" \
    --application "$foreign_app" \
    --destination "$destination" \
    --no-relaunch
assert_contains "$(cat "$TMP_DIR/stderr")" "bundle identifier" \
    "foreign bundle rejection must be actionable"
[[ "$(cat "$destination/Contents/Resources/marker.txt")" == "replacement" ]] || \
    fail "a rejected installation must preserve the installed application"

symlink_destination="$TMP_DIR/Symlinked.app"
ln -s "$destination" "$symlink_destination"
assert_fails "local installation must reject a destination symlink" \
    "$ROOT/scripts/install-local.sh" \
    --application "$replacement_app" \
    --destination "$symlink_destination" \
    --no-relaunch
assert_contains "$(cat "$TMP_DIR/stderr")" "symbolic link" \
    "destination symlink rejection must be actionable"

assert_fails "local installation must reject an in-place source" \
    "$ROOT/scripts/install-local.sh" \
    --application "$destination" \
    --destination "$destination" \
    --no-relaunch
assert_contains "$(cat "$TMP_DIR/stderr")" "different paths" \
    "in-place source rejection must be actionable"

release_script="$(cat "$ROOT/scripts/release.sh")"
[[ "$release_script" != *"install-local.sh"* ]] || \
    fail "release artifact generation must not install an application"
[[ "$release_script" != *"build-and-install.sh"* ]] || \
    fail "release artifact generation must not invoke the local installation routine"

printf 'Local installation tests passed\n'
