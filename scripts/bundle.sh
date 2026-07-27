#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="${BETTERTOT_BUILD_NUMBER:-1}"
SIGN_IDENTITY="${BETTERTOT_SIGN_IDENTITY:--}"
OUTPUT="$ROOT/dist/BetterTot.app"

usage() {
    cat <<'EOF'
Usage: scripts/bundle.sh [options]

Build a universal BetterTot.app bundle.

Options:
  --version VERSION         Marketing version (default: VERSION file)
  --build-number NUMBER     Numeric bundle build number (default: 1)
  --sign-identity IDENTITY  codesign identity; '-' performs ad-hoc signing
  --output PATH             Destination .app path
  --help                    Show this help
EOF
}

die() {
    printf 'bundle.sh: %s\n' "$1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ $# -ge 2 ]] || die "--version requires a value"
            VERSION="$2"
            shift 2
            ;;
        --build-number)
            [[ $# -ge 2 ]] || die "--build-number requires a value"
            BUILD_NUMBER="$2"
            shift 2
            ;;
        --sign-identity)
            [[ $# -ge 2 ]] || die "--sign-identity requires a value"
            SIGN_IDENTITY="$2"
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
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || \
    die "build number must be a positive integer"
[[ "$OUTPUT" == *.app ]] || die "output must end in .app"

mkdir -p "$(dirname "$OUTPUT")"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/bettertot-bundle.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/BetterTot.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cd "$ROOT"
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
swift build -c release --arch arm64 --arch x86_64
cp "$BIN_DIR/BetterTot" "$APP/Contents/MacOS/BetterTot"
cp "$ROOT/LICENSE" "$ROOT/NOTICE" "$APP/Contents/Resources/"
cp "$ROOT/Assets/MenuBarIcon.png" "$APP/Contents/Resources/"
"$ROOT/scripts/generate-app-icon.sh" \
    --output "$APP/Contents/Resources/BetterTot.icns"

"$ROOT/scripts/generate-info-plist.sh" \
    --version "$VERSION" \
    --build-number "$BUILD_NUMBER" \
    --output "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP"
    SIGNING_DESCRIPTION="ad-hoc signed; local use only"
else
    codesign \
        --force \
        --options runtime \
        --timestamp \
        --sign "$SIGN_IDENTITY" \
        "$APP"
    SIGNING_DESCRIPTION="signed with $SIGN_IDENTITY"
fi
codesign --verify --deep --strict --verbose=2 "$APP"

if [[ -e "$OUTPUT" ]]; then
    [[ "$OUTPUT" != "/" && "$OUTPUT" != "$ROOT" ]] || die "refusing unsafe output path"
    rm -rf "$OUTPUT"
fi
mv "$APP" "$OUTPUT"
printf 'Built %s (%s)\n' "$OUTPUT" "$SIGNING_DESCRIPTION"
