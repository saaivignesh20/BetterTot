#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd -P)"

fail() {
    printf 'coverage_tooling_test.sh: %s\n' "$1" >&2
    exit 1
}

[[ -x "$ROOT/scripts/check-coverage.sh" ]] || \
    fail "scripts/check-coverage.sh must exist and be executable"

help_output="$("$ROOT/scripts/check-coverage.sh" --help)"
[[ "$help_output" == *"--minimum"* ]] || fail "coverage help must document --minimum"
[[ "$help_output" == *"--file-minimum"* ]] || \
    fail "coverage help must document --file-minimum"
[[ "$help_output" == *"--coverage-json"* ]] || \
    fail "coverage help must document --coverage-json"

fixture="$(mktemp "${TMPDIR:-/tmp}/bettertot-coverage.XXXXXX")"
trap 'rm -f "$fixture"' EXIT
cat > "$fixture" <<JSON
{
  "data": [{
    "files": [
      {
        "filename": "$ROOT/Sources/BetterTot/One.swift",
        "summary": {"lines": {"count": 80, "covered": 64}}
      },
      {
        "filename": "$ROOT/Tests/BetterTotTests/OneTests.swift",
        "summary": {"lines": {"count": 100, "covered": 100}}
      }
    ]
  }]
}
JSON

"$ROOT/scripts/check-coverage.sh" \
    --minimum 80 \
    --file-minimum 80 \
    --coverage-json "$fixture" >/dev/null

if "$ROOT/scripts/check-coverage.sh" --minimum 81 --coverage-json "$fixture" >/dev/null 2>&1; then
    fail "coverage below the minimum must fail"
fi

if "$ROOT/scripts/check-coverage.sh" \
    --minimum 80 \
    --file-minimum 81 \
    --coverage-json "$fixture" >/dev/null 2>&1; then
    fail "per-file coverage below the minimum must fail"
fi

if "$ROOT/scripts/check-coverage.sh" --minimum invalid --coverage-json "$fixture" >/dev/null 2>&1; then
    fail "invalid minimum must fail"
fi

printf 'Coverage tooling tests passed\n'
