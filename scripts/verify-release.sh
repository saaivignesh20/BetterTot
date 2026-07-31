#!/bin/bash
set -euo pipefail

VERSION=""
DIRECTORY=""
REQUIRE_NOTARIZED=false

die() {
    printf 'verify-release.sh: %s\n' "$1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ $# -ge 2 ]] || die "--version requires a value"
            VERSION="$2"
            shift 2
            ;;
        --directory)
            [[ $# -ge 2 ]] || die "--directory requires a value"
            DIRECTORY="$2"
            shift 2
            ;;
        --require-notarized)
            REQUIRE_NOTARIZED=true
            shift
            ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
    die "version must be a semantic version such as 1.2.3"
[[ -d "$DIRECTORY" ]] || die "release directory does not exist: $DIRECTORY"

ZIP_NAME="BetterTot-$VERSION.zip"
CHECKSUM_NAME="BetterTot-$VERSION.sha256"
ZIP="$DIRECTORY/$ZIP_NAME"
CHECKSUM="$DIRECTORY/$CHECKSUM_NAME"
[[ -f "$ZIP" ]] || die "missing archive: $ZIP"
[[ -f "$CHECKSUM" ]] || die "missing checksum: $CHECKSUM"
ARCHIVE_ENTRIES="$(unzip -Z1 "$ZIP")"
if grep -E '(^|/)\._' <<< "$ARCHIVE_ENTRIES" >/dev/null; then
    die "archive contains AppleDouble metadata files"
fi
UNEXPECTED_ENTRY="$(awk \
    '!/^BetterTot\.app\// || /(^|\/)\.\.(\/|$)/ || /^\// || /\\/ { print; exit }' \
    <<< "$ARCHIVE_ENTRIES")"
if [[ -n "$UNEXPECTED_ENTRY" ]]; then
    die "unexpected archive entry: $UNEXPECTED_ENTRY"
fi

(
    cd "$DIRECTORY"
    shasum -a 256 -c "$CHECKSUM_NAME"
)

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bettertot-verify.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
ditto -x -k "$ZIP" "$TMP_DIR"
APP="$TMP_DIR/BetterTot.app"
[[ -d "$APP" ]] || die "archive does not contain BetterTot.app at its root"
[[ -f "$APP/Contents/Resources/LICENSE" ]] || \
    die "archive does not contain the Apache 2.0 license"
[[ -f "$APP/Contents/Resources/NOTICE" ]] || \
    die "archive does not contain the project notice"
grep -q "Version 2.0, January 2004" "$APP/Contents/Resources/LICENSE" || \
    die "bundled license is not Apache License 2.0"

PLIST="$APP/Contents/Info.plist"
plutil -lint "$PLIST" >/dev/null
ACTUAL_VERSION="$(plutil -extract CFBundleShortVersionString raw "$PLIST")"
[[ "$ACTUAL_VERSION" == "$VERSION" ]] || \
    die "archive version $ACTUAL_VERSION does not match requested version $VERSION"

ARCHITECTURES="$(lipo -archs "$APP/Contents/MacOS/BetterTot")"
[[ " $ARCHITECTURES " == *" arm64 "* ]] || die "archive is missing arm64 support"
[[ " $ARCHITECTURES " == *" x86_64 "* ]] || die "archive is missing x86_64 support"
codesign --verify --deep --strict --verbose=2 "$APP"

if [[ "$REQUIRE_NOTARIZED" == true ]]; then
    xcrun stapler validate "$APP"
    spctl --assess --type execute --verbose=2 "$APP"
fi

printf 'Verified BetterTot %s (%s)\n' "$VERSION" "$ARCHITECTURES"
