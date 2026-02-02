#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Building..."
swift build

echo "Creating app bundle..."
mkdir -p build/TalkKey.app/Contents/MacOS
mkdir -p build/TalkKey.app/Contents/Resources

cp .build/debug/PressToTalk build/TalkKey.app/Contents/MacOS/TalkKey
chmod +x build/TalkKey.app/Contents/MacOS/TalkKey

cat > build/TalkKey.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>TalkKey</string>
    <key>CFBundleDisplayName</key>
    <string>TalkKey</string>
    <key>CFBundleIdentifier</key>
    <string>com.talkkey.app</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>TalkKey</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>TalkKey needs microphone access to record your voice for transcription.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

# Add icon
iconutil -c icns AppIcon.iconset -o build/TalkKey.app/Contents/Resources/AppIcon.icns

echo "Launching..."
open build/TalkKey.app
