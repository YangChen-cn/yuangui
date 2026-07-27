#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="YuanGUI"
BUNDLE_ID="com.yang.yuangui"
MIN_SYSTEM_VERSION="15.0"
APP_VERSION="2.7.0"
APP_BUILD="16"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCE_BUNDLE_NAME="${APP_NAME}_${APP_NAME}.bundle"

if [[ "$MODE" != "build-only" && "$MODE" != "--build-only" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

cd "$ROOT_DIR"
swift build
BIN_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BIN_DIR/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

RESOURCE_BUNDLE="$BIN_DIR/$RESOURCE_BUNDLE_NAME"
if [[ ! -d "$RESOURCE_BUNDLE" ]]; then
  echo "missing SwiftPM resource bundle: $RESOURCE_BUNDLE" >&2
  exit 1
fi
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

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>YuanGUI</string>
  <key>CFBundleDisplayName</key>
  <string>YuanGUI</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleLocalizations</key>
  <array><string>en</string><string>zh-Hans</string></array>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
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

# Keep a stable local code requirement for ServiceManagement login-item registration.
/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --build-only|build-only)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      if pgrep -x "$APP_NAME" >/dev/null; then
        exit 0
      fi
      sleep 0.25
    done
    echo "$APP_NAME did not remain running after launch" >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--build-only|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
