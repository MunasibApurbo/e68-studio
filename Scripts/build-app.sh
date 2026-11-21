#!/bin/bash
# Builds "dist/E68 Studio.app". Needs only the Xcode Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p dist
APP="dist/E68 Studio.app"
swift build -c release --disable-sandbox

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/E68Studio "$APP/Contents/MacOS/E68Studio"

ICON_TMP="$(mktemp -d)"
trap 'rm -rf "$ICON_TMP"' EXIT
ICONSET="$ICON_TMP/AppIcon.iconset"
swift Scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cp Resources/ukiru-mat.jpg "$APP/Contents/Resources/"
cp Resources/ASSET_CREDITS.md "$APP/Contents/Resources/"
cp -R Resources/VIA "$APP/Contents/Resources/"
cp -R Resources/Environments "$APP/Contents/Resources/"
cp -R Resources/Plants "$APP/Contents/Resources/"
cp -R Resources/Materials "$APP/Contents/Resources/"

BUNDLE_ID="${BUNDLE_ID:-local.e68studio}"
APP_VERSION="${APP_VERSION:-1.0}"
APP_BUILD="${APP_BUILD:-1}"
APP_COPYRIGHT="${APP_COPYRIGHT:-Copyright © 2026 E68 Studio.}"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>E68 Studio</string>
    <key>CFBundleDisplayName</key><string>E68 Studio</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>E68Studio</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
    <key>CFBundleVersion</key><string>${APP_BUILD}</string>
    <key>NSHumanReadableCopyright</key><string>${APP_COPYRIGHT}</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
    <key>NSAudioCaptureUsageDescription</key><string>E68 Studio reads system audio playback to synchronize keyboard lighting with music.</string>
    <key>NSBluetoothAlwaysUsageDescription</key><string>E68 Studio reads battery levels from your E-68 PRO keyboard and MCHOSE G7 mouse over Bluetooth.</string>
    <key>NSScreenCaptureUsageDescription</key><string>E68 Studio samples colours from your screen to match keyboard lighting to what you are watching.</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

find "$APP" -name '.DS_Store' -delete
xattr -cr "$APP"

SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"E68StudioLocal"'; then
    SIGN_IDENTITY="E68StudioLocal"
fi
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="-"
fi

if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign "-" --entitlements Scripts/E68Studio.entitlements "$APP"
else
    codesign --force --options runtime --timestamp --entitlements Scripts/E68Studio.entitlements --sign "$SIGN_IDENTITY" "$APP"
fi
echo "Built $PWD/$APP (signed with: $SIGN_IDENTITY)"
