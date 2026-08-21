#!/bin/bash
# Builds a styled, signed TalkKey.dmg from an already-built build/TalkKey.app.
#
# The Finder window layout (background image, icon positions, view options) is
# baked into the volume's .DS_Store, which only Finder can write — so the
# volume has to be mounted under /Volumes while AppleScript configures it.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="TalkKey"
VOL_NAME="TalkKey"
DEVELOPER_ID="Developer ID Application: Aleksei Koledachkin (TQ5423H59B)"
SRC_APP="build/$APP_NAME.app"
RW_DMG="build/$APP_NAME.rw.dmg"
OUT_DMG="build/$APP_NAME.dmg"
MOUNT="/Volumes/$VOL_NAME"

# Window geometry — must match assets/dmg-background.png (660x420 @1x)
WIN_W=660
WIN_H=420
TITLEBAR=28
ICON_SIZE=128
APP_X=175;  APP_Y=215
APPS_X=485; APPS_Y=215

[ -d "$SRC_APP" ] || { echo "❌ $SRC_APP not found — run ./release.sh first"; exit 1; }

echo "💿 Building styled DMG..."

hdiutil detach "$MOUNT" -force >/dev/null 2>&1 || true
rm -f "$RW_DMG" "$OUT_DMG"

# Size the image from the payload plus slack for the filesystem overhead
SIZE_KB=$(du -sk "$SRC_APP" | cut -f1)
SIZE_MB=$(( SIZE_KB / 1024 + 24 ))

hdiutil create -size ${SIZE_MB}m -fs HFS+ -volname "$VOL_NAME" -ov "$RW_DMG" >/dev/null
hdiutil attach "$RW_DMG" -noverify -noautoopen >/dev/null

ditto "$SRC_APP" "$MOUNT/$APP_NAME.app"
ln -s /Applications "$MOUNT/Applications"

mkdir -p "$MOUNT/.background"
cp assets/dmg-background.tiff "$MOUNT/.background/background.tiff"

# Custom volume icon (shown in Finder's sidebar and on the desktop)
cp build/$APP_NAME.app/Contents/Resources/AppIcon.icns "$MOUNT/.VolumeIcon.icns"
SetFile -a C "$MOUNT" 2>/dev/null || echo "⚠️  SetFile unavailable — volume icon not set"

echo "🎨 Applying Finder layout..."
osascript <<EOD
tell application "Finder"
    tell disk "$VOL_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 140, 200 + $WIN_W, 140 + $WIN_H + $TITLEBAR}

        set opts to the icon view options of container window
        set arrangement of opts to not arranged
        set icon size of opts to $ICON_SIZE
        set text size of opts to 13
        set label position of opts to bottom
        set shows item info of opts to false
        set shows icon preview of opts to true
        set background picture of opts to file ".background:background.tiff"

        set position of item "$APP_NAME.app" of container window to {$APP_X, $APP_Y}
        set position of item "Applications" of container window to {$APPS_X, $APPS_Y}

        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOD

# Let Finder flush .DS_Store before unmounting
sync
sleep 2

hdiutil detach "$MOUNT" >/dev/null || hdiutil detach "$MOUNT" -force >/dev/null
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$OUT_DMG" >/dev/null
rm -f "$RW_DMG"

echo "🔏 Signing DMG..."
codesign --force --sign "$DEVELOPER_ID" "$OUT_DMG"
codesign --verify --verbose "$OUT_DMG" 2>&1 | tail -1

echo ""
ls -lh "$OUT_DMG"
echo "✅ $OUT_DMG"
echo ""
echo "📤 Notarize it:"
echo "xcrun notarytool submit $OUT_DMG --key ./AuthKey_L4XCLS9466.p8 --key-id L4XCLS9466 --issuer 470df7ff-0cf0-4be9-a6ce-b27d6db7078d --wait"
echo "xcrun stapler staple $OUT_DMG"
