#!/bin/bash
# Packages the release build into a distributable .dmg.
#
# Run `flutter build macos --release` first, or pass --build to have this do it.
# Output lands in dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Shuttle"
VOL_NAME="$APP_NAME"
APP="$ROOT/build/macos/Build/Products/Release/$APP_NAME.app"
DIST="$ROOT/dist"
DMG="$DIST/$APP_NAME.dmg"
STAGE="$(mktemp -d)"
MOUNT=""

cleanup() {
  [[ -n "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$STAGE"
}
trap cleanup EXIT

if [[ "${1:-}" == "--build" ]]; then
  ( cd "$ROOT" && flutter build macos --release )
fi

[[ -d "$APP" ]] || { echo "No app at $APP — run: flutter build macos --release" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
echo "==> Packaging $APP_NAME $VERSION"

# ── Stage the disk image contents ────────────────────────────────────────
mkdir -p "$DIST"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

mkdir -p "$STAGE/.background"
# A plain PNG renders soft on Retina. A multi-representation TIFF gives Finder
# both the 1x and 2x images, and it picks the right one per display.
tiffutil -cathidpicheck \
  "$ROOT/packaging/dmg_background.png" \
  "$ROOT/packaging/dmg_background@2x.png" \
  -out "$STAGE/.background/background.tiff" >/dev/null

# ── Build a writable image, dress it, then compress ──────────────────────
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 40 ))
RW="$STAGE.rw.dmg"
rm -f "$RW" "$DMG"
hdiutil create -srcfolder "$STAGE" -volname "$VOL_NAME" -fs HFS+ \
  -format UDRW -size "${SIZE_MB}m" "$RW" >/dev/null

MOUNT="/Volumes/$VOL_NAME"
hdiutil attach "$RW" -mountpoint "$MOUNT" -nobrowse -quiet

# Window size, icon placement and background. Finder automation needs the
# terminal to hold Automation permission; a refusal only costs the layout.
osascript <<EOF || echo "    (warning: Finder layout skipped — grant Automation access to run this)"
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 860, 560}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set background picture of opts to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of container window to {165, 205}
    set position of item "Applications" of container window to {495, 205}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF

# The volume icon goes on last. Finder strips it if it is already in place
# when the layout pass runs — the icon file disappears and the custom-icon
# bit comes back cleared.
cp "$ROOT/packaging/VolumeIcon.icns" "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT" || echo "    (warning: could not set the volume icon bit)"

sync
hdiutil detach "$MOUNT" -quiet
MOUNT=""

hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"

echo "==> $DMG ($(du -h "$DMG" | cut -f1))"
