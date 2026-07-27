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
[[ "$WORKFLOW" == *'--notes-file dist/publish/release-notes.md'* ]] || \
    fail "draft release must use the curated notes artifact"
[[ "$WORKFLOW" != *'--generate-notes'* ]] || \
    fail "generated notes must not replace curated initial-release notes"

printf 'Release notes tests passed\n'
