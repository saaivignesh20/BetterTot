#!/bin/bash
set -euo pipefail

VERSION=""
SHA256=""
REPOSITORY=""

die() {
    printf 'render-cask.sh: %s\n' "$1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ $# -ge 2 ]] || die "--version requires a value"
            VERSION="$2"
            shift 2
            ;;
        --sha256)
            [[ $# -ge 2 ]] || die "--sha256 requires a value"
            SHA256="$2"
            shift 2
            ;;
        --repository)
            [[ $# -ge 2 ]] || die "--repository requires a value"
            REPOSITORY="$2"
            shift 2
            ;;
        *) die "unknown option: $1" ;;
    esac
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
    die "version must be a semantic version such as 1.2.3"
[[ "$SHA256" =~ ^[0-9a-f]{64}$ ]] || die "sha256 must contain 64 lowercase hexadecimal characters"
[[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || \
    die "repository must use owner/name format"

cat <<CASK
cask "bettertot" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/$REPOSITORY/releases/download/v#{version}/BetterTot-#{version}.zip"
  name "BetterTot"
  desc "Native macOS menu-bar scratchpad with eight fixed pads"
  homepage "https://github.com/$REPOSITORY"

  depends_on macos: ">= :ventura"

  app "BetterTot.app"

  uninstall quit: "org.bettertot.BetterTot"
end
CASK
