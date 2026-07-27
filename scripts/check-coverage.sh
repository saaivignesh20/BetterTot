#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
MINIMUM="${BETTERTOT_MINIMUM_COVERAGE:-80}"
FILE_MINIMUM="${BETTERTOT_MINIMUM_FILE_COVERAGE:-30}"
COVERAGE_JSON=""

usage() {
    cat <<'EOF'
Usage: scripts/check-coverage.sh [options]

Check aggregate line coverage for Swift files under Sources/.

Options:
  --minimum PERCENT       Required line coverage (default: 80)
  --file-minimum PERCENT  Required coverage per non-entry source file (default: 30)
  --coverage-json PATH    SwiftPM code coverage JSON to inspect
  --help                  Show this help
EOF
}

die() {
    printf 'check-coverage.sh: %s\n' "$1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --minimum)
            [[ $# -ge 2 ]] || die "--minimum requires a value"
            MINIMUM="$2"
            shift 2
            ;;
        --coverage-json)
            [[ $# -ge 2 ]] || die "--coverage-json requires a path"
            COVERAGE_JSON="$2"
            shift 2
            ;;
        --file-minimum)
            [[ $# -ge 2 ]] || die "--file-minimum requires a value"
            FILE_MINIMUM="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ "$MINIMUM" =~ ^([0-9]+)(\.[0-9]+)?$ ]] || die "minimum must be a number from 0 to 100"
awk -v value="$MINIMUM" 'BEGIN { exit !(value >= 0 && value <= 100) }' || \
    die "minimum must be a number from 0 to 100"
[[ "$FILE_MINIMUM" =~ ^([0-9]+)(\.[0-9]+)?$ ]] || \
    die "file minimum must be a number from 0 to 100"
awk -v value="$FILE_MINIMUM" 'BEGIN { exit !(value >= 0 && value <= 100) }' || \
    die "file minimum must be a number from 0 to 100"

if [[ -z "$COVERAGE_JSON" ]]; then
    COVERAGE_JSON="$(cd "$ROOT" && swift test --show-codecov-path | tail -n 1)"
fi
[[ -f "$COVERAGE_JSON" ]] || die "coverage JSON does not exist: $COVERAGE_JSON"

ruby -rjson -e '
  root = (File.expand_path(ARGV.fetch(0)) + File::SEPARATOR).downcase
  minimum = Float(ARGV.fetch(1))
  report = JSON.parse(File.read(ARGV.fetch(2)))
  file_minimum = Float(ARGV.fetch(3))
  files = report.fetch("data").flat_map { |entry| entry.fetch("files") }
  source_files = files.select do |file|
    File.expand_path(file.fetch("filename")).downcase.start_with?(root)
  end
  abort("check-coverage.sh: report contains no source files") if source_files.empty?

  counts = source_files.sum { |file| file.dig("summary", "lines", "count") }
  covered = source_files.sum { |file| file.dig("summary", "lines", "covered") }
  abort("check-coverage.sh: source line count is zero") if counts.zero?

  percent = covered.fdiv(counts) * 100
  printf("Line coverage: %.2f%% (%d/%d), minimum %.2f%%\n", percent, covered, counts, minimum)

  below_file_minimum = source_files.each_with_object([]) do |file, failures|
    next if File.basename(file.fetch("filename")) == "App.swift"
    lines = file.dig("summary", "lines")
    file_percent = lines.fetch("covered").fdiv(lines.fetch("count")) * 100
    if file_percent + Float::EPSILON < file_minimum
      failures << [File.basename(file.fetch("filename")), file_percent]
    end
  end
  below_file_minimum.each do |name, file_percent|
    warn format("check-coverage.sh: %s coverage %.2f%% is below %.2f%%", name, file_percent, file_minimum)
  end
  exit 1 if percent + Float::EPSILON < minimum || !below_file_minimum.empty?
' "$ROOT/Sources" "$MINIMUM" "$COVERAGE_JSON" "$FILE_MINIMUM"
