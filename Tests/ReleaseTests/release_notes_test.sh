#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORKFLOW="$(cat "$ROOT/.github/workflows/release.yml")"

fail() {
    printf 'release_notes_test.sh: %s\n' "$1" >&2
    exit 1
}

[[ -f "$ROOT/docs/releases/0.1.0.md" ]] || fail "0.1.0 release notes are missing"
[[ "$WORKFLOW" == *'docs/releases/$version.md'* ]] || \
    fail "release workflow must select notes matching VERSION"
[[ "$WORKFLOW" == *'dist/tagged/release-notes.md'* ]] || \
    fail "tagged artifact must include the curated release notes"
[[ "$(cat "$ROOT/docs/releases/0.1.0.md")" == *'BetterTot-0.1.0.pkg'* ]] || \
    fail "release notes must document the installer package"
[[ "$WORKFLOW" != *'gh release create'* ]] || \
    fail "tagged builds must not create a public GitHub Release"

printf 'Release notes tests passed\n'
