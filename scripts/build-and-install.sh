#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
BUILD_NUMBER="${BETTERTOT_BUILD_NUMBER:-1}"
SIGN_IDENTITY="${BETTERTOT_SIGN_IDENTITY:--}"
DESTINATION="/Applications/BetterTot.app"
PACKAGE_OUTPUT=""
RELAUNCH=true
DRY_RUN=false

usage() {
    cat <<'EOF'
Usage: scripts/build-and-install.sh [options]

Build BetterTot.app and its local .pkg, install the exact built app at
/Applications/BetterTot.app, and relaunch it after a successful update.

Options:
  --version VERSION         Marketing version (default: VERSION file)
  --build-number NUMBER     Numeric bundle build number (default: 1)
  --sign-identity IDENTITY  codesign identity; '-' performs ad-hoc signing
  --package-output PATH     Package path (default: dist/BetterTot-VERSION.pkg)
  --destination PATH        Installed app (default: /Applications/BetterTot.app)
  --no-relaunch             Quit BetterTot but do not reopen it after installation
  --dry-run                 Validate options and show the planned update
  --help                    Show this help
EOF
}

die() {
    printf 'build-and-install.sh: %s\n' "$1" >&2
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
        --package-output)
            [[ $# -ge 2 ]] || die "--package-output requires a value"
            PACKAGE_OUTPUT="$2"
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
[[ "$DESTINATION" == *.app ]] || die "destination must end in .app"

APP="$ROOT/dist/BetterTot.app"
if [[ -z "$PACKAGE_OUTPUT" ]]; then
    PACKAGE_OUTPUT="$ROOT/dist/BetterTot-$VERSION.pkg"
fi
[[ "$PACKAGE_OUTPUT" == *.pkg ]] || die "package output must end in .pkg"

printf 'Application: %s\n' "$APP"
printf 'Package: %s\n' "$PACKAGE_OUTPUT"
printf 'Installation: %s\n' "$DESTINATION"
if [[ "$DRY_RUN" == true ]]; then
    exit 0
fi

"$ROOT/scripts/bundle.sh" \
    --version "$VERSION" \
    --build-number "$BUILD_NUMBER" \
    --sign-identity "$SIGN_IDENTITY" \
    --output "$APP"

"$ROOT/scripts/package-installer.sh" \
    --version "$VERSION" \
    --application "$APP" \
    --output "$PACKAGE_OUTPUT"

INSTALL_ARGUMENTS=(
    --application "$APP"
    --destination "$DESTINATION"
)
if [[ "$RELAUNCH" == false ]]; then
    INSTALL_ARGUMENTS+=(--no-relaunch)
fi
"$ROOT/scripts/install-local.sh" "${INSTALL_ARGUMENTS[@]}"

printf 'Built the package and updated the local BetterTot installation.\n'
