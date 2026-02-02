#!/bin/bash
set -e

# Configuration
APP_NAME="TalkKey"
BUNDLE_ID="com.talkkey.app"
DEVELOPER_ID="Developer ID Application: Aleksei Koledachkin (TQ5423H59B)"
TEAM_ID="TQ5423H59B"

# Get version from argument or prompt
VERSION=${1:-""}
if [ -z "$VERSION" ]; then
    echo "Current version in build:"
    grep -A1 "CFBundleShortVersionString" build/$APP_NAME.app/Contents/Info.plist 2>/dev/null | tail -1 || echo "  (no build yet)"
    echo ""
    read -p "Enter new version (e.g., 1.1): " VERSION
fi

echo "🔨 Building $APP_NAME v$VERSION (release)..."

# Build release
swift build -c release

# Create app bundle
rm -rf build/$APP_NAME.app
mkdir -p build/$APP_NAME.app/Contents/MacOS
mkdir -p build/$APP_NAME.app/Contents/Resources

cp .build/release/PressToTalk build/$APP_NAME.app/Contents/MacOS/$APP_NAME
chmod +x build/$APP_NAME.app/Contents/MacOS/$APP_NAME

# Copy resource bundle with WhisperKit model
if [ -d ".build/release/PressToTalk_PressToTalk.bundle" ]; then
    cp -R .build/release/PressToTalk_PressToTalk.bundle build/$APP_NAME.app/Contents/Resources/
    echo "✅ Copied WhisperKit model bundle"
fi

# Copy Sparkle framework
mkdir -p build/$APP_NAME.app/Contents/Frameworks
cp -R .build/arm64-apple-macosx/release/Sparkle.framework build/$APP_NAME.app/Contents/Frameworks/
echo "✅ Copied Sparkle framework"

# Add rpath for embedded frameworks
install_name_tool -add_rpath "@executable_path/../Frameworks" build/$APP_NAME.app/Contents/MacOS/$APP_NAME
echo "✅ Added Frameworks rpath"

# Create Info.plist with new version
cat > build/$APP_NAME.app/Contents/Info.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>$APP_NAME needs microphone access to record your voice for transcription.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/manikosto/talkkey/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>q6Y0bCYUf7EIvydAODsGVuxi5J786SXSgRFiaAbgs4A=</string>
</dict>
</plist>
EOF

# Add icon
iconutil -c icns AppIcon.iconset -o build/$APP_NAME.app/Contents/Resources/AppIcon.icns

echo "🔏 Signing with entitlements..."
codesign --force --deep --options runtime --entitlements TalkKey.entitlements --sign "$DEVELOPER_ID" build/$APP_NAME.app

echo "📦 Creating zip for notarization..."
cd build
rm -f $APP_NAME.zip
ditto -c -k --keepParent $APP_NAME.app $APP_NAME.zip
cd ..

echo ""
echo "✅ Build complete: build/$APP_NAME.app (v$VERSION)"
echo ""
echo "📤 Next step - notarize (run this command):"
echo ""
echo "xcrun notarytool submit build/$APP_NAME.zip \\"
echo "  --apple-id \"YOUR_APPLE_ID\" \\"
echo "  --team-id \"$TEAM_ID\" \\"
echo "  --password \"YOUR_APP_SPECIFIC_PASSWORD\" \\"
echo "  --wait"
echo ""
echo "📎 After notarization succeeds:"
echo "xcrun stapler staple build/$APP_NAME.app"
echo ""
echo "💿 Create DMG:"
echo "rm -f build/$APP_NAME.dmg && hdiutil create -volname \"$APP_NAME\" -srcfolder build/$APP_NAME.app -ov -format UDZO build/$APP_NAME.dmg"
