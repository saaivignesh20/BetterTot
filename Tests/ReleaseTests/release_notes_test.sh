#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW="$(cat "$ROOT/.github/workflows/release.yml")"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
NOTES="$ROOT/docs/releases/$VERSION.md"

fail() {
    printf 'release_notes_test.sh: %s\n' "$1" >&2
    exit 1
}

[[ -f "$NOTES" ]] || fail "$VERSION release notes are missing"
[[ "$WORKFLOW" == *'docs/releases/$version.md'* ]] || \
    fail "release workflow must select notes matching VERSION"
[[ "$WORKFLOW" == *'dist/tagged/release-notes.md'* ]] || \
    fail "tagged artifact must include the curated release notes"
[[ "$(cat "$NOTES")" == *"BetterTot-$VERSION.pkg"* ]] || \
    fail "release notes must document the installer package"
[[ "$WORKFLOW" != *'gh release create'* ]] || \
    fail "tagged builds must not create a public GitHub Release"

printf 'Release notes tests passed\n'
