#!/bin/bash
set -u
fail=0
pass(){ echo "PASS  $1"; }
bad(){ echo "FAIL  $1"; fail=$((fail+1)); }

APP="$HOME/Applications/Focus.app"
BIN="$APP/Contents/MacOS/Focus"
DEADLOCK="/Applications/deadlock.app/Contents/MacOS/deadlock"
EXPECTED_VERSION="1.7.1"

[[ -d "$APP" ]] && pass "Focus.app installed" || bad "Focus.app installed"
[[ -x "$BIN" ]] && pass "Focus executable" || bad "Focus executable"

VERSION=""
if [[ -f "$APP/Contents/Info.plist" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
fi

if [[ "$VERSION" == "$EXPECTED_VERSION" ]]; then
  pass "Focus version $EXPECTED_VERSION"
else
  bad "Focus version $EXPECTED_VERSION (installed: ${VERSION:-unknown})"
fi

if [[ -x "$BIN" ]] && "$BIN" --integration-check 2>/dev/null | grep -q 'integration ready v1.7'; then
  pass "calendar integration helper v1.7"
else
  bad "calendar integration helper v1.7"
fi

if [[ -x "$DEADLOCK" ]]; then
  pass "deadlock CLI installed"
  "$DEADLOCK" --ipc status >/dev/null 2>&1     && pass "deadlock daemon bridge reachable"     || bad "deadlock daemon bridge reachable"
else
  bad "deadlock CLI installed"
fi

pgrep -x Focus >/dev/null 2>&1 && pass "Focus menu process running" || bad "Focus menu process running"

echo
exit "$fail"
