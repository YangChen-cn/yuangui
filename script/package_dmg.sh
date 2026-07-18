#!/usr/bin/env bash
set -euo pipefail

APP_NAME="YuanGUI"
DISPLAY_NAME="元圭与 VCC"
BUNDLE_ID="com.yang.yuangui"
VERSION="${VERSION:-1.0.5}"
MIN_SYSTEM_VERSION="14.0"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
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
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>7</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>用于在你确认后控制 Music App 播放，并让 Finder 执行废纸篓操作。</string>
  <key>NSLocationUsageDescription</key>
  <string>用于获取你所在区域的当前天气，只请求公里级位置且不保存轨迹。</string>
  <key>NSLocationWhenInUseUsageDescription</key>
  <string>用于获取你所在区域的当前天气，只请求公里级位置且不保存轨迹。</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
  SIGNING_NOTE="这是个人分享版，使用临时签名。首次打开请按下方说明操作。"
else
  /usr/bin/codesign --force --deep --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
  SIGNING_NOTE="此版本已使用 Apple Developer ID 签名。"
fi

/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

/usr/bin/ditto "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
printf '%s\n' \
  "$DISPLAY_NAME $VERSION 安装说明" \
  "" \
  "1. 将 YuanGUI.app 拖到旁边的 Applications 文件夹。" \
  "2. 在“应用程序”中找到 YuanGUI。首次打开时建议按住 Control 点击应用，再选择“打开”。" \
  "3. 如果系统仍拦截，请前往“系统设置 → 隐私与安全性”，点击“仍要打开”。" \
  "4. 首次使用天气时允许位置权限；AI 对话需要在设置中填写你自己的 API Key。" \
  "" \
  "$SIGNING_NOTE" \
  "支持系统：macOS 14 或更高版本。" \
  >"$STAGING_DIR/安装说明.txt"

/usr/bin/hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    echo "NOTARY_PROFILE requires a Developer ID Application signing identity" >&2
    exit 1
  fi
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

/usr/bin/hdiutil verify "$DMG_PATH"
rm -rf "$STAGING_DIR"

echo "Created: $DMG_PATH"
echo "SHA-256: $(/usr/bin/shasum -a 256 "$DMG_PATH" | /usr/bin/awk '{print $1}')"
