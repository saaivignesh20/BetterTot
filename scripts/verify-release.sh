#!/bin/bash
set -euo pipefail

VERSION=""
DIRECTORY=""

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
        *) die "unknown option: $1" ;;
    esac
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
    die "version must be a semantic version such as 1.2.3"
[[ -d "$DIRECTORY" ]] || die "release directory does not exist: $DIRECTORY"

ZIP_NAME="BetterTot-$VERSION.zip"
PKG_NAME="BetterTot-$VERSION.pkg"
CHECKSUM_NAME="BetterTot-$VERSION.sha256"
ZIP="$DIRECTORY/$ZIP_NAME"
PKG="$DIRECTORY/$PKG_NAME"
CHECKSUM="$DIRECTORY/$CHECKSUM_NAME"
[[ -f "$ZIP" ]] || die "missing archive: $ZIP"
[[ -f "$PKG" ]] || die "missing installer: $PKG"
[[ -f "$CHECKSUM" ]] || die "missing checksum: $CHECKSUM"
CHECKSUM_TARGETS="$(awk 'NF { print $2 }' "$CHECKSUM" | LC_ALL=C sort)"
EXPECTED_TARGETS="$(printf '%s\n%s\n' "$PKG_NAME" "$ZIP_NAME" | LC_ALL=C sort)"
[[ "$CHECKSUM_TARGETS" == "$EXPECTED_TARGETS" ]] || \
    die "checksum must cover exactly $ZIP_NAME and $PKG_NAME"
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

PKG_PAYLOAD="$(pkgutil --payload-files "$PKG")"
PKG_UNEXPECTED="$(awk '
    /(^|\/)\.\.(\/|$)/ || /^\// || /\\/ { print; exit }
    $0 != "." && $0 != "./BetterTot.app" &&
        $0 !~ /^\.\/BetterTot\.app\// { print; exit }
' <<< "$PKG_PAYLOAD")"
if [[ -n "$PKG_UNEXPECTED" ]]; then
    die "unexpected installer payload entry: $PKG_UNEXPECTED"
fi
if grep -E '(^|/)\._|(^|/)\.__' <<< "$PKG_PAYLOAD" >/dev/null; then
    die "installer payload contains AppleDouble metadata"
fi

PKG_EXPANDED="$TMP_DIR/installer"
pkgutil --expand-full "$PKG" "$PKG_EXPANDED"
[[ ! -e "$PKG_EXPANDED/Scripts" ]] || \
    die "installer must not contain privileged scripts"
PACKAGE_INFO="$PKG_EXPANDED/PackageInfo"
[[ "$(xmllint --xpath 'string(/pkg-info/@identifier)' "$PACKAGE_INFO")" == \
    "org.bettertot.BetterTot.pkg" ]] || die "installer identifier is invalid"
[[ "$(xmllint --xpath 'string(/pkg-info/@version)' "$PACKAGE_INFO")" == "$VERSION" ]] || \
    die "installer version does not match requested version"
[[ "$(xmllint --xpath 'string(/pkg-info/@install-location)' "$PACKAGE_INFO")" == \
    "/Applications" ]] || die "installer destination is not /Applications"
PKG_APP="$PKG_EXPANDED/Payload/BetterTot.app"
[[ -d "$PKG_APP" ]] || die "installer does not contain BetterTot.app"
diff -qr "$APP" "$PKG_APP" >/dev/null || \
    die "installer application does not match the ZIP application"
codesign --verify --deep --strict --verbose=2 "$PKG_APP"

printf 'Verified BetterTot %s ZIP and installer (%s)\n' "$VERSION" "$ARCHITECTURES"
