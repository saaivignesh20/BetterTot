#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift test --enable-code-coverage
scripts/check-coverage.sh
Tests/ReleaseTests/release_tooling_test.sh
Tests/ReleaseTests/coverage_tooling_test.sh
Tests/ReleaseTests/release_notes_test.sh
