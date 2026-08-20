#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APPLICATION="$ROOT/dist/BetterTot.app"
DESTINATION="/Applications/BetterTot.app"
EXPECTED_IDENTIFIER="org.bettertot.BetterTot"
RELAUNCH=true

usage() {
    cat <<'EOF'
Usage: scripts/install-local.sh [options]

Safely replace a local BetterTot installation with a verified app bundle.

Options:
  --application PATH   Source BetterTot.app (default: dist/BetterTot.app)
  --destination PATH   Installed app (default: /Applications/BetterTot.app)
  --no-relaunch        Quit BetterTot but do not reopen it after installation
  --help               Show this help

The destination parent must be writable. This command never modifies
BetterTot data under Library/Application Support.
EOF
}

die() {
    printf 'install-local.sh: %s\n' "$1" >&2
    exit 1
}

bundle_value() {
    local app="$1"
    local key="$2"
    plutil -extract "$key" raw "$app/Contents/Info.plist" 2>/dev/null || true
}

validate_bettertot_app() {
    local app="$1"
    local description="$2"
    if [[ ! -d "$app" || -L "$app" ]]; then
        printf 'install-local.sh: %s is not a plain app bundle: %s\n' \
            "$description" "$app" >&2
        return 1
    fi
    if [[ ! -f "$app/Contents/Info.plist" ]]; then
        printf 'install-local.sh: %s has no Info.plist: %s\n' \
            "$description" "$app" >&2
        return 1
    fi

    local identifier
    identifier="$(bundle_value "$app" CFBundleIdentifier)"
    if [[ "$identifier" != "$EXPECTED_IDENTIFIER" ]]; then
        printf 'install-local.sh: %s has unexpected bundle identifier: %s\n' \
            "$description" "${identifier:-missing}" >&2
        return 1
    fi

    local executable
    executable="$(bundle_value "$app" CFBundleExecutable)"
    if [[ -z "$executable" || ! -x "$app/Contents/MacOS/$executable" ]]; then
        printf 'install-local.sh: %s has no executable declared by Info.plist\n' \
            "$description" >&2
        return 1
    fi
    if ! codesign --verify --deep --strict --verbose=2 "$app" >/dev/null 2>&1; then
        printf 'install-local.sh: %s has an invalid code signature\n' \
            "$description" >&2
        return 1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --application)
            [[ $# -ge 2 ]] || die "--application requires a value"
            APPLICATION="$2"
            shift 2
            ;;
        --destination)
            [[ $# -ge 2 ]] || die "--destination requires a value"
            DESTINATION="$2"
            shift 2
            ;;
        --no-relaunch)
            RELAUNCH=false
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ "$APPLICATION" == *.app ]] || die "application must be an .app bundle"
[[ "$DESTINATION" == *.app ]] || die "destination must be an .app bundle path"
validate_bettertot_app "$APPLICATION" "source application" || \
    die "source application validation failed"

APPLICATION_PARENT="$(cd "$(dirname "$APPLICATION")" && pwd -P)"
APPLICATION="$APPLICATION_PARENT/$(basename "$APPLICATION")"
DESTINATION_PARENT="$(cd "$(dirname "$DESTINATION")" 2>/dev/null && pwd -P)" || \
    die "destination parent does not exist: $(dirname "$DESTINATION")"
DESTINATION="$DESTINATION_PARENT/$(basename "$DESTINATION")"

[[ "$APPLICATION" != "$DESTINATION" ]] || \
    die "source application and destination must be different paths"
[[ -w "$DESTINATION_PARENT" ]] || \
    die "destination is not writable: $DESTINATION_PARENT"

if [[ -e "$DESTINATION" || -L "$DESTINATION" ]]; then
    [[ ! -L "$DESTINATION" ]] || die "refusing to replace a symbolic link: $DESTINATION"
    validate_bettertot_app "$DESTINATION" "installed application" || \
        die "installed application validation failed"
fi

STAGING="$(mktemp -d "$DESTINATION_PARENT/.bettertot-install.XXXXXX")"
STAGED_APP="$STAGING/BetterTot.app"
ATOMIC_REPLACE="$STAGING/atomic-replace"

cleanup() {
    rm -rf "$STAGING"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ditto --norsrc --noextattr "$APPLICATION" "$STAGED_APP"
validate_bettertot_app "$STAGED_APP" "staged application" || \
    die "staged application validation failed"
xcrun clang -std=c11 -Wall -Wextra -Werror -O2 \
    "$ROOT/scripts/atomic-replace.c" \
    -o "$ATOMIC_REPLACE"

RUNNING_APP_INFO="$(lsappinfo info -only bundlepath -only pid \
    "$EXPECTED_IDENTIFIER" 2>/dev/null || true)"
RUNNING_BUNDLE_PATH="$(printf '%s\n' "$RUNNING_APP_INFO" |
    sed -n 's/.*bundle path="\([^"]*\)".*/\1/p')"
RUNNING_PID="$(printf '%s\n' "$RUNNING_APP_INFO" |
    sed -n 's/.*pid = \([0-9][0-9]*\).*/\1/p')"
if [[ -n "$RUNNING_PID" && "$RUNNING_BUNDLE_PATH" == "$DESTINATION" ]]; then
    if ! osascript -e \
        'tell application id "org.bettertot.BetterTot" to quit' >/dev/null; then
        die "could not ask BetterTot to quit; quit it manually and rerun"
    fi
    for _ in {1..100}; do
        kill -0 "$RUNNING_PID" >/dev/null 2>&1 || break
        sleep 0.1
    done
    kill -0 "$RUNNING_PID" >/dev/null 2>&1 && \
        die "BetterTot did not quit within 10 seconds; installation was not changed"
fi

if [[ -e "$DESTINATION" || -L "$DESTINATION" ]]; then
    [[ ! -L "$DESTINATION" ]] || die "refusing to replace a symbolic link: $DESTINATION"
    validate_bettertot_app "$DESTINATION" "installed application" || \
        die "installed application validation failed"
fi

REPLACEMENT_MODE="$("$ATOMIC_REPLACE" "$STAGED_APP" "$DESTINATION")" || \
    die "could not atomically replace the installed application"

if ! validate_bettertot_app "$DESTINATION" "installed application"; then
    if [[ "$REPLACEMENT_MODE" == "swapped" ]]; then
        "$ATOMIC_REPLACE" "$STAGED_APP" "$DESTINATION" >/dev/null || \
            die "installed application failed verification and rollback failed"
    else
        "$ATOMIC_REPLACE" "$DESTINATION" "$STAGED_APP" >/dev/null || \
            die "installed application failed verification and rollback failed"
    fi
    die "installed application failed verification; restored the previous state"
fi

VERSION="$(bundle_value "$DESTINATION" CFBundleShortVersionString)"
if [[ "$RELAUNCH" == true ]]; then
    open "$DESTINATION" || die "BetterTot was installed but could not be relaunched"
fi

printf 'Installed BetterTot %s at %s\n' "${VERSION:-unknown}" "$DESTINATION"
