#!/usr/bin/env bash
set -euo pipefail

APP_NAME="YuanGUI"
DISPLAY_NAME="YuanGUI"
BUNDLE_ID="com.yang.yuangui"
: "${VERSION:?VERSION is required, for example VERSION=2.7.2}"
: "${BUILD:?BUILD is required, for example BUILD=18}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)*$ ]] || {
  echo "VERSION must be a stable numeric version such as 2.7.2: $VERSION" >&2
  exit 1
}
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || {
  echo "BUILD must be a positive integer: $BUILD" >&2
  exit 1
}
MIN_SYSTEM_VERSION="15.0"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-YuanGui}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_PLUGINS="$APP_CONTENTS/PlugIns"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCE_BUNDLE_NAME="${APP_NAME}_${APP_NAME}.bundle"
STAGING_DIR="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/YuanGUI-$VERSION.dmg"

cd "$ROOT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BUILD_BINARY="$BIN_DIR/$APP_NAME"
RESOURCE_BUNDLE="$BIN_DIR/$RESOURCE_BUNDLE_NAME"

if [[ ! -x "$BUILD_BINARY" ]]; then
  echo "missing release executable: $BUILD_BINARY" >&2
  exit 1
fi
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "missing SwiftPM resource bundle: $RESOURCE_BUNDLE" >&2
  exit 1
fi

rm -rf "$APP_BUNDLE" "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$STAGING_DIR"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
cp "$ROOT_DIR/Sources/YuanGUI/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
for locale in en zh-Hans; do
  cp -R "$ROOT_DIR/Sources/YuanGUI/Resources/Localization/$locale.lproj" "$APP_RESOURCES/"
done
mkdir -p "$APP_RESOURCES/Legal"
for legal_file in LICENSE ASSET_LICENSE.md THIRD_PARTY_NOTICES.md; do
  if [[ -f "$ROOT_DIR/$legal_file" ]]; then
    cp "$ROOT_DIR/$legal_file" "$APP_RESOURCES/Legal/"
  fi
done

"$ROOT_DIR/script/build_finder_extension.sh" \
  Release "$VERSION" "$BUILD" \
  "$APP_PLUGINS/YuanGUIFinderExtension.appex" "$SIGNING_IDENTITY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array><string>en</string><string>zh-Hans</string></array>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Allows YuanGUI to control Music after you request playback, and to ask Finder to move selected cleanup items to the Trash.</string>
  <key>NSLocationUsageDescription</key>
  <string>Allows YuanGUI to show weather for your approximate location. It does not store location history.</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>Allows YuanGUI to show weather for your approximate location. It does not store location history.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Allows YuanGUI to capture the screen area you explicitly select for OCR translation, local editing, copying, or saving.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# The default `YuanGui` identity is intentionally self-signed. It must not be
# timestamped or described as Developer ID signed; callers who provide an
# Apple-issued identity can still opt into the hardened-runtime/timestamp path.
if [[ "$SIGNING_IDENTITY" == "YuanGui" ]]; then
  /usr/bin/codesign --force --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
  SIGNING_NOTE="此版本已使用 YuanGui 自签名证书签名。"
else
  /usr/bin/codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
  SIGNING_NOTE="此版本已使用指定的代码签名身份签名。"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

/usr/bin/ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
for dmg_document in Install.txt 安装说明.txt LICENSE ASSET_LICENSE.md THIRD_PARTY_NOTICES.md; do
  cp "$ROOT_DIR/$dmg_document" "$STAGING_DIR/$dmg_document"
done

/usr/bin/hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ "$SIGNING_IDENTITY" == "YuanGui" ]]; then
    echo "NOTARY_PROFILE requires an Apple-issued Developer ID Application signing identity" >&2
    exit 1
  fi
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

/usr/bin/hdiutil verify "$DMG_PATH"
rm -rf "$STAGING_DIR"

echo "Created: $DMG_PATH"
echo "Version: $VERSION"
echo "Build: $BUILD"
echo "Minimum system version: $MIN_SYSTEM_VERSION"
echo "Size: $(/usr/bin/stat -f '%z' "$DMG_PATH")"
echo "SHA-256: $(/usr/bin/shasum -a 256 "$DMG_PATH" | /usr/bin/awk '{print $1}')"
