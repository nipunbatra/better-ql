#!/usr/bin/env bash
# Better QL — remove the app and unregister the Quick Look extension.
# Usage: ./uninstall.sh
set -uo pipefail

APP_NAME="BetterQL"
EXT_ID="com.nipunbatra.BetterQL.Preview"
DEST="/Applications/${APP_NAME}.app"

echo "▸ Removing extension registration…"
pluginkit -r "${DEST}/Contents/PlugIns/${APP_NAME}Preview.appex" 2>/dev/null || true
pluginkit -e ignore -i "${EXT_ID}" 2>/dev/null || true

echo "▸ Deleting ${DEST}…"
killall "${APP_NAME}" 2>/dev/null || true
pkill -f "${APP_NAME}Preview" 2>/dev/null || true
rm -rf "${DEST}"

echo "▸ Resetting Quick Look…"
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true
killall QuickLookUIService 2>/dev/null || true

echo "✓ Uninstalled. (If .md still shows the old type, log out/in to fully clear Launch Services.)"
