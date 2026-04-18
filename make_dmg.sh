#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

rm -f build/TalkKey.dmg build/TalkKey.rw.dmg
rm -rf /tmp/talkkey_mnt
mkdir -p /tmp/talkkey_mnt

hdiutil create -size 20m -fs HFS+ -volname TalkKey -ov build/TalkKey.rw.dmg

# Mount OUTSIDE /Volumes to bypass App Management TCC, which keys off the /Volumes/ prefix.
hdiutil attach -nobrowse -noverify -noautoopen -mountpoint /tmp/talkkey_mnt build/TalkKey.rw.dmg

ditto build/TalkKey.app /tmp/talkkey_mnt/TalkKey.app

hdiutil detach /tmp/talkkey_mnt

hdiutil convert build/TalkKey.rw.dmg -format UDZO -ov -o build/TalkKey.dmg
rm -f build/TalkKey.rw.dmg
rmdir /tmp/talkkey_mnt 2>/dev/null || true

ls -lh build/TalkKey.dmg
