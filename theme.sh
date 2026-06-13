#!/usr/bin/env bash
# Better QL — set the preview appearance: light | dark | system
# Usage: ./theme.sh light|dark|system
set -euo pipefail

MODE="${1:-}"
case "$MODE" in
  light|dark|system) ;;
  *) echo "usage: ./theme.sh light|dark|system"; exit 1 ;;
esac

APP="/Applications/BetterQL.app"
APPEX="${APP}/Contents/PlugIns/BetterQLPreview.appex"
[ -d "$APPEX" ] || { echo "Better QL isn't installed. Run ./install.sh first."; exit 1; }

# Preserve each bundle's entitlements across the re-sign (so the sandbox stays intact).
ENT_EXT="$(mktemp)"; ENT_APP="$(mktemp)"
codesign -d --entitlements - --xml "$APPEX" > "$ENT_EXT" 2>/dev/null
codesign -d --entitlements - --xml "$APP"   > "$ENT_APP" 2>/dev/null

echo "$MODE" > "${APPEX}/Contents/Resources/theme.txt"

# Modifying a bundle resource invalidates the signature, so re-sign (inner first).
codesign --force --sign - --entitlements "$ENT_EXT" "$APPEX"
codesign --force --sign - --entitlements "$ENT_APP" "$APP"

qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true
killall QuickLookUIService quicklookd 2>/dev/null || true

echo "✓ Better QL theme set to: ${MODE}"
echo "  Open a fresh Quick Look preview to see it."
