#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

[[ "$(uname -s)" == "Darwin" ]] || {
  echo "Focus installs only on macOS." >&2
  exit 1
}

command -v swift >/dev/null 2>&1 || {
  echo "Swift was not found." >&2
  echo "Install Apple's Command Line Tools with: xcode-select --install" >&2
  exit 1
}

echo "== Focus installer =="
echo "This builds Focus locally from the source in this repository."
echo

./build.sh

APP="$HOME/Applications/Focus.app"
[[ -x "$APP/Contents/MacOS/Focus" ]] || {
  echo "ERROR: installation finished but Focus.app was not found." >&2
  exit 1
}

echo
echo "Done. Focus is installed at:"
echo "  $APP"
