#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

[[ "$(uname -s)" == "Darwin" ]] || {
    echo "Focus builds only on macOS." >&2
    exit 1
}

echo "== Focus v1.7 release build =="

if ! swift build -c release; then
    echo
    echo "ERROR: Focus v1.7 did not compile."
    echo "Your previously installed Focus.app was left untouched."
    exit 1
fi

BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/Focus"

[[ -x "$BIN" ]] || {
    echo "ERROR: release executable not found at $BIN" >&2
    exit 1
}

APP="$HOME/Applications/Focus.app"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/focus-app.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/Focus.app/Contents/MacOS"
cp "$BIN" "$STAGE/Focus.app/Contents/MacOS/Focus"

cat > "$STAGE/Focus.app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.focus</string>
    <key>CFBundleName</key><string>Focus</string>
    <key>CFBundleDisplayName</key><string>Focus</string>
    <key>CFBundleExecutable</key><string>Focus</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>8</string>
    <key>CFBundleShortVersionString</key><string>1.7</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>LSMultipleInstancesProhibited</key><true/>
</dict>
</plist>
EOF

plutil -lint "$STAGE/Focus.app/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - "$STAGE/Focus.app"
/usr/bin/codesign --verify --deep --strict "$STAGE/Focus.app"

pkill -x Focus 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$APP"
mv "$STAGE/Focus.app" "$APP"

open -g "$APP"

echo
echo "Installed Focus v1.7 to $APP"
