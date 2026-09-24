#!/bin/bash
set -euo pipefail

APP="$HOME/Applications/Focus.app"

pkill -x Focus 2>/dev/null || true
rm -rf "$APP"

echo "Removed $APP"
echo "Session history in ~/Library/Application Support/Focus was left intact."
