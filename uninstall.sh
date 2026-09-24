#!/bin/bash
set -euo pipefail

[[ "$(uname -s)" == "Darwin" ]] || { echo "error: macOS only." >&2; exit 1; }

pkill -x Focus 2>/dev/null || true
rm -rf "$HOME/Applications/Focus.app"

echo "Focus.app removed."
echo "Session history and preferences were kept."
