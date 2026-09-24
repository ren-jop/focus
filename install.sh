#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SNAPSHOT="$ROOT/source/focus-v1.7.zip.b64"

fail() { echo "error: $*" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "Focus supports macOS only."
command -v xcrun >/dev/null 2>&1 || fail "Install Apple's Command Line Tools first: xcode-select --install"
xcrun --find swift >/dev/null 2>&1 || fail "Swift was not found. Install Apple's Command Line Tools: xcode-select --install"
[[ -f "$SNAPSHOT" ]] || fail "Bundled source snapshot is missing."

WORK="$(mktemp -d "${TMPDIR:-/tmp}/focus-install.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

echo "== Focus v1.7 preview =="
/usr/bin/base64 -D < "$SNAPSHOT" > "$WORK/focus.zip"
/usr/bin/unzip -tq "$WORK/focus.zip" >/dev/null || fail "Bundled source snapshot failed its integrity check."
/usr/bin/ditto -x -k "$WORK/focus.zip" "$WORK"

SRC="$WORK/FocusShare-calendar-deadlock-v1.7"
[[ -f "$SRC/Package.swift" ]] || fail "Bundled source snapshot is invalid."
chmod +x "$SRC/build.sh"

echo "Building and installing..."
cd "$SRC"
./build.sh

echo
echo "Installed: $HOME/Applications/Focus.app"
echo "Open Focus from ~/Applications or Spotlight."
