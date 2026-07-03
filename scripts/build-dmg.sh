#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="VibeNotch"
BIN_NAME="VibeNotch"
BUNDLE_ID="com.vibenotch.app"
VERSION="1.7.0"
BUILD_DIR=".build"
STAGE_DIR="$BUILD_DIR/dmg-stage"
APP_DIR="$STAGE_DIR/$APP_NAME.app"
# Final DMG lands at the project root so it's visible in Finder (.build is hidden).
DMG_PATH="$APP_NAME-$VERSION.dmg"

# Universal binary requires full Xcode (xcbuild). Fall back to host-only when
# only Command Line Tools are installed.
if xcrun --find xcbuild >/dev/null 2>&1; then
    echo "==> Building universal release binary (arm64 + x86_64)"
    swift build -c release --arch arm64 --arch x86_64
else
    echo "==> Building release binary (host arch only — install Xcode for universal)"
    swift build -c release
fi

echo "==> Assembling $APP_NAME.app"
rm -rf "$STAGE_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Universal builds land under .build/apple/Products/Release, not .build/release.
UNIVERSAL_BIN="$BUILD_DIR/apple/Products/Release/$BIN_NAME"
SINGLE_BIN="$BUILD_DIR/release/$BIN_NAME"
if [ -f "$UNIVERSAL_BIN" ]; then
    cp "$UNIVERSAL_BIN" "$APP_DIR/Contents/MacOS/$BIN_NAME"
else
    cp "$SINGLE_BIN" "$APP_DIR/Contents/MacOS/$BIN_NAME"
fi
echo "    architectures: $(lipo -archs "$APP_DIR/Contents/MacOS/$BIN_NAME" 2>/dev/null || echo unknown)"

if [ -f icon/AppIcon.icns ]; then
    echo "==> Bundling AppIcon.icns"
    cp icon/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
else
    echo "==> WARNING: icon/AppIcon.icns missing — app will ship without an icon. Run scripts/build-appicon.sh to generate it."
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$BIN_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Prefer a stable signing identity if available — keeps the Keychain ACL
# stable across rebuilds so "Always Allow" persists. Falls back to ad-hoc
# when the identity isn't installed (first build / contributors).
#
# Override the identity name with VIBENOTCH_SIGN_IDENTITY in the environment.
# Run ./scripts/setup-signing-identity.sh once to install the default.
SIGN_IDENTITY="${VIBENOTCH_SIGN_IDENTITY:-VibeNotch Self-Signed}"
if security find-identity -p codesigning 2>/dev/null | grep -F "$SIGN_IDENTITY" >/dev/null; then
    echo "==> Codesigning with '$SIGN_IDENTITY'"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR" >/dev/null
else
    echo "==> Ad-hoc codesigning (no stable identity — run scripts/setup-signing-identity.sh to fix the keychain re-prompt)"
    codesign --force --deep --sign - "$APP_DIR" >/dev/null
fi

echo "==> Building DMG at $DMG_PATH"
rm -f "$DMG_PATH"
# Symlink so the user can drag-install into /Applications.
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "==> Done"
echo "DMG: $DMG_PATH"
ls -lh "$DMG_PATH"
