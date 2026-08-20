#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Assets/AppIcon.svg"
OUTPUT="$ROOT/Assets/BetterTot.icns"

usage() {
    cat <<'EOF'
Usage: scripts/generate-app-icon.sh [--output PATH]

Generate BetterTot.icns from the original SVG master.
EOF
}

die() {
    printf 'generate-app-icon.sh: %s\n' "$1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
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

[[ -f "$SOURCE" ]] || die "SVG master does not exist: $SOURCE"
[[ "$OUTPUT" == *.icns ]] || die "output must end in .icns"
command -v sips >/dev/null || die "sips is required"
command -v iconutil >/dev/null || die "iconutil is required"

mkdir -p "$(dirname "$OUTPUT")"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/bettertot-icon.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ICONSET="$STAGING/BetterTot.iconset"
MASTER="$STAGING/master.png"
mkdir -p "$ICONSET"

if ! sips --setProperty format png "$SOURCE" --out "$MASTER" >/dev/null 2>&1; then
    command -v qlmanage >/dev/null || \
        die "sips could not rasterize the SVG and qlmanage is unavailable"
    qlmanage -t -s 1024 -o "$STAGING" "$SOURCE" >/dev/null 2>&1 || \
        die "could not rasterize the SVG master"
    QL_PREVIEW="$STAGING/$(basename "$SOURCE").png"
    [[ -f "$QL_PREVIEW" ]] || die "Quick Look did not produce an icon preview"
    mv "$QL_PREVIEW" "$MASTER"
fi

render() {
    local pixels="$1"
    local name="$2"
    sips --resampleHeightWidth "$pixels" "$pixels" "$MASTER" \
        --out "$ICONSET/$name" >/dev/null
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil --convert icns --output "$OUTPUT" "$ICONSET"
