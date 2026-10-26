#!/bin/zsh
# Builds Gauge.app (release), signs it ad-hoc, and optionally installs to /Applications.
#   ./scripts/build.sh            -> build/Gauge.app
#   ./scripts/build.sh --install  -> also copies to /Applications and launches
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Gauge"
BUNDLE_ID="dev.8air.Gauge"
VERSION="1.0.0"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "▸ Compiling (release)…"
swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/$APP_NAME"
[[ -x "$BIN" ]] || { echo "build failed"; exit 1; }

echo "▸ Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

if [[ -f Resources/AppIcon.png ]]; then
  if [[ ! -f "$BUILD_DIR/AppIcon.icns" || Resources/AppIcon.png -nt "$BUILD_DIR/AppIcon.icns" ]]; then
    echo "▸ Generating icon…"
    rm -rf "$BUILD_DIR/AppIcon.iconset"
    swift scripts/make_icon.swift Resources/AppIcon.png "$BUILD_DIR/AppIcon.iconset" >/dev/null
    iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$BUILD_DIR/AppIcon.icns"
  fi
  cp "$BUILD_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>Gauge — AI usage tracker</string>
</dict>
</plist>
PLIST

echo "▸ Signing (ad-hoc)…"
codesign --force --deep --sign - --options runtime "$APP" >/dev/null
echo "✓ Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "▸ Installing to /Applications…"
  pkill -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP_NAME.app" || true
  open "/Applications/$APP_NAME.app"
  echo "✓ Installed and launched /Applications/$APP_NAME.app"
fi
