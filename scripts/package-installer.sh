#!/bin/bash
set -euo pipefail

VERSION=""
APPLICATION=""
OUTPUT=""
PACKAGE_IDENTIFIER="org.bettertot.BetterTot.pkg"

usage() {
    cat <<'EOF'
Usage: scripts/package-installer.sh [options]

Create an unsigned macOS installer package for BetterTot.

Options:
  --version VERSION      Semantic version embedded in the package
  --application PATH     BetterTot.app to install
  --output PATH          Destination .pkg path
  --help                 Show this help

The package installs BetterTot.app into /Applications. It is unsigned and
unnotarized, matching the repository-only ad-hoc release scope.
EOF
}

die() {
    printf 'package-installer.sh: %s\n' "$1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ $# -ge 2 ]] || die "--version requires a value"
            VERSION="$2"
            shift 2
            ;;
        --application)
            [[ $# -ge 2 ]] || die "--application requires a value"
            APPLICATION="$2"
            shift 2
            ;;
        --output)
            [[ $# -ge 2 ]] || die "--output requires a value"
            OUTPUT="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
    die "version must be a semantic version such as 1.2.3"
[[ -d "$APPLICATION" ]] || die "application does not exist: $APPLICATION"
[[ "$APPLICATION" == *.app ]] || die "application must be an .app bundle"
[[ -n "$OUTPUT" && "$OUTPUT" == *.pkg ]] || die "output must be a .pkg path"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bettertot-installer.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

STAGED_APP="$TMP_DIR/root/BetterTot.app"
RAW_PACKAGE="$TMP_DIR/raw.pkg"
EXPANDED_PACKAGE="$TMP_DIR/expanded"
FINAL_PACKAGE="$TMP_DIR/BetterTot.pkg"

mkdir -p "$TMP_DIR/root" "$(dirname "$OUTPUT")"
ditto --norsrc --noextattr "$APPLICATION" "$STAGED_APP"
codesign --verify --deep --strict --verbose=2 "$STAGED_APP"

PKGBUILD_LOG="$TMP_DIR/pkgbuild.log"
if ! pkgbuild \
    --component "$STAGED_APP" \
    --install-location /Applications \
    --identifier "$PACKAGE_IDENTIFIER" \
    --version "$VERSION" \
    "$RAW_PACKAGE" >"$PKGBUILD_LOG" 2>&1; then
    cat "$PKGBUILD_LOG" >&2
    die "pkgbuild failed"
fi

# Newer macOS versions may project protected provenance xattrs as AppleDouble
# files. Rebuild pkgbuild's payload from controlled paths so the installer
# never writes those sidecars into /Applications.
pkgutil --expand "$RAW_PACKAGE" "$EXPANDED_PACKAGE"
(
    cd "$TMP_DIR/root"
    find . -print | COPYFILE_DISABLE=1 cpio -o --format odc 2>/dev/null |
        gzip -c > "$EXPANDED_PACKAGE/Payload"
)
mkbom "$TMP_DIR/root" "$EXPANDED_PACKAGE/Bom"
pkgutil --flatten "$EXPANDED_PACKAGE" "$FINAL_PACKAGE"

if pkgutil --payload-files "$FINAL_PACKAGE" |
    grep -E '(^|/)\._|(^|/)\.__' >/dev/null; then
    die "installer payload contains AppleDouble metadata"
fi

mv "$FINAL_PACKAGE" "$OUTPUT"
printf 'Built unsigned installer %s\n' "$OUTPUT"
