#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
  echo "usage: $0 <Debug|Release> <version> <build> <destination.appex> <signing-identity>" >&2
  exit 2
fi

CONFIGURATION="$1"
APP_VERSION="$2"
APP_BUILD="$3"
DESTINATION="$4"
SIGNING_IDENTITY="$5"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT_DIR/FinderExtension/YuanGUIFinderExtension.xcodeproj"
case "$CONFIGURATION" in
  Debug) DERIVED_SUFFIX="debug" ;;
  Release) DERIVED_SUFFIX="release" ;;
  *) echo "unsupported configuration: $CONFIGURATION" >&2; exit 2 ;;
esac
DERIVED_DATA="$ROOT_DIR/.build/finder-extension-derived-$DERIVED_SUFFIX"
PRODUCT="$DERIVED_DATA/Build/Products/$CONFIGURATION/YuanGUIFinderExtension.appex"
ENTITLEMENTS="$ROOT_DIR/FinderExtension/Extension/YuanGUIFinderExtension.entitlements"

xcodebuild \
  -project "$PROJECT" \
  -scheme YuanGUIFinderExtension \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  MARKETING_VERSION="$APP_VERSION" \
  CURRENT_PROJECT_VERSION="$APP_BUILD" \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_DEBUG_DYLIB=NO \
  build

if [[ ! -d "$PRODUCT" ]]; then
  echo "missing Finder extension product: $PRODUCT" >&2
  exit 1
fi

rm -rf "$DESTINATION"
mkdir -p "$(dirname "$DESTINATION")"
/usr/bin/ditto "$PRODUCT" "$DESTINATION"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  /usr/bin/codesign --force --sign - --entitlements "$ENTITLEMENTS" "$DESTINATION"
else
  /usr/bin/codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" "$DESTINATION"
fi

/usr/bin/codesign --verify --strict --verbose=2 "$DESTINATION"
