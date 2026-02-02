#!/bin/bash
# Signs a DMG for Sparkle updates and outputs the signature
# Usage: ./sign_update.sh dist/TalkKey.dmg

if [ -z "$1" ]; then
    echo "Usage: $0 <path-to-dmg>"
    exit 1
fi

DMG_PATH="$1"

if [ ! -f "$DMG_PATH" ]; then
    echo "Error: File not found: $DMG_PATH"
    exit 1
fi

# Get file size
SIZE=$(stat -f%z "$DMG_PATH")

# Sign with Sparkle
SIGNATURE=$(.build/artifacts/sparkle/Sparkle/bin/sign_update "$DMG_PATH" 2>&1)

echo ""
echo "=== Sparkle Update Info ==="
echo "File: $DMG_PATH"
echo "Size: $SIZE bytes"
echo "Signature: $SIGNATURE"
echo ""
echo "=== For appcast.xml ==="
echo "<enclosure"
echo "    url=\"https://talkkey.io/releases/$(basename $DMG_PATH)\""
echo "    sparkle:edSignature=\"$SIGNATURE\""
echo "    length=\"$SIZE\""
echo "    type=\"application/octet-stream\"/>"
