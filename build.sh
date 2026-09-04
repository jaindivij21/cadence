#!/usr/bin/env bash
# Builds Cadence.app and, unless you pass --no-install, moves it to /Applications.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/.build/release"
APP="$ROOT/Cadence.app"
INSTALL_DIR="/Applications"
BUNDLE_ID="com.divijjain.cadence"
VERSION="1.0.0"

INSTALL=1
for arg in "$@"; do
  [ "$arg" = "--no-install" ] && INSTALL=0
done

echo "==> Compiling"
cd "$ROOT"
swift build -c release

echo "==> Drawing the icon"
ICONSET="$ROOT/.build/Cadence.iconset"
rm -rf "$ICONSET"
swift "$ROOT/Tools/makeicon.swift" "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$ROOT/.build/Cadence.icns"

echo "==> Assembling the bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/Cadence" "$APP/Contents/MacOS/Cadence"
cp "$ROOT/.build/Cadence.icns" "$APP/Contents/Resources/Cadence.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Cadence</string>
    <key>CFBundleDisplayName</key><string>Cadence</string>
    <key>CFBundleExecutable</key><string>Cadence</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>Cadence</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT licensed.</string>
</dict>
</plist>
PLIST

echo "==> Signing (ad hoc)"
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "    codesign failed; the app still runs, macOS will just ask once."

if [ "$INSTALL" -eq 1 ]; then
  echo "==> Installing to $INSTALL_DIR"
  # Quit a running copy so the binary is not busy.
  pkill -x Cadence 2>/dev/null || true
  sleep 1
  rm -rf "$INSTALL_DIR/Cadence.app"
  mv "$APP" "$INSTALL_DIR/Cadence.app"
  echo "==> Done. Open it with: open -a Cadence"
else
  echo "==> Done. Bundle is at $APP"
fi
