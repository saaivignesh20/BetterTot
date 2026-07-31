#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="${BETTERTOT_BUILD_NUMBER:-1}"
SIGN_IDENTITY="${BETTERTOT_SIGN_IDENTITY:--}"
REPOSITORY=""
DRY_RUN=false
SKIP_TESTS=false

usage() {
    cat <<'EOF'
Usage: scripts/release.sh [options]

Create versioned BetterTot ZIP and .pkg artifacts with a SHA-256 checksum.

Options:
  --version VERSION         Semantic version (default: VERSION file)
  --build-number NUMBER     Numeric bundle build number (default: 1)
  --sign-identity IDENTITY  Developer ID Application identity; '-' is local-only
  --repository OWNER/REPO   Render a matching Homebrew Cask
  --skip-tests              Skip test execution
  --dry-run                 Validate options and show planned artifacts only
  --help                    Show this help

Environment equivalents:
  BETTERTOT_BUILD_NUMBER, BETTERTOT_SIGN_IDENTITY
EOF
}

die() {
    printf 'release.sh: %s\n' "$1" >&2
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
        --repository)
            [[ $# -ge 2 ]] || die "--repository requires a value"
            REPOSITORY="$2"
            shift 2
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
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
if [[ -n "$REPOSITORY" && ! "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
    die "repository must use owner/name format"
fi
OUT="$ROOT/dist/release"
APP="$OUT/BetterTot.app"
ZIP_NAME="BetterTot-$VERSION.zip"
PKG_NAME="BetterTot-$VERSION.pkg"
CHECKSUM_NAME="BetterTot-$VERSION.sha256"
ZIP="$OUT/$ZIP_NAME"
PKG="$OUT/$PKG_NAME"

printf 'Version: %s (%s)\n' "$VERSION" "$BUILD_NUMBER"
printf 'Application: %s\n' "$APP"
printf 'Archive: %s\n' "$ZIP"
printf 'Installer: %s\n' "$PKG"
printf 'Checksum: %s/%s\n' "$OUT" "$CHECKSUM_NAME"

if [[ "$DRY_RUN" == true ]]; then
    exit 0
fi

if [[ "$SKIP_TESTS" == false ]]; then
    "$ROOT/scripts/test.sh"
fi

mkdir -p "$OUT"
rm -f "$ZIP" "$PKG" "$OUT/$CHECKSUM_NAME" "$OUT/bettertot.rb"
"$ROOT/scripts/bundle.sh" \
    --version "$VERSION" \
    --build-number "$BUILD_NUMBER" \
    --sign-identity "$SIGN_IDENTITY" \
    --output "$APP"

ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"

"$ROOT/scripts/package-installer.sh" \
    --version "$VERSION" \
    --application "$APP" \
    --output "$PKG"

(
    cd "$OUT"
    shasum -a 256 "$ZIP_NAME" "$PKG_NAME" > "$CHECKSUM_NAME"
)

if [[ -n "$REPOSITORY" ]]; then
    SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
    "$ROOT/scripts/render-cask.sh" \
        --version "$VERSION" \
        --sha256 "$SHA256" \
        --repository "$REPOSITORY" > "$OUT/bettertot.rb"
fi

"$ROOT/scripts/verify-release.sh" \
    --version "$VERSION" \
    --directory "$OUT"

printf 'Release artifacts are ready in %s\n' "$OUT"
