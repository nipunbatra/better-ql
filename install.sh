#!/usr/bin/env bash
# Better QL — build, install, and register the Quick Look preview extension.
# Usage: ./install.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="BetterQL"
EXT_ID="com.nipunbatra.BetterQL.Preview"
DEST="/Applications/${APP_NAME}.app"

echo "▸ Generating Xcode project…"
xcodegen generate >/dev/null

echo "▸ Building (ad-hoc / run-locally signing)…"
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" \
  -configuration Debug -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES \
  build >/dev/null

APP="build/Build/Products/Debug/${APP_NAME}.app"

echo "▸ Installing to ${DEST}…"
killall "${APP_NAME}" 2>/dev/null || true
pkill -f "${APP_NAME}Preview" 2>/dev/null || true
rm -rf "${DEST}"
ditto "${APP}" "${DEST}"

echo "▸ Registering the extension…"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister
"${LSREGISTER}" -f "${DEST}"
pluginkit -a "${DEST}/Contents/PlugIns/${APP_NAME}Preview.appex" 2>/dev/null || true
pluginkit -e use -i "${EXT_ID}" 2>/dev/null || true

echo "▸ Resetting Quick Look…"
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true
killall QuickLookUIService 2>/dev/null || true
killall quicklookd 2>/dev/null || true

echo
echo "✓ Installed. Registered extension:"
pluginkit -m -i "${EXT_ID}" || true
echo
echo "Press Space in Finder on a .md file, a .zip, or a folder."
echo "If a type doesn't preview, enable 'Better QL Preview' under:"
echo "  System Settings ▸ General ▸ Login Items & Extensions ▸ Quick Look"
