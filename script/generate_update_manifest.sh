#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_DIR="$ROOT_DIR/updates"
MANIFEST_PATH="${UPDATE_MANIFEST_PATH:-$MANIFEST_DIR/latest.json}"

: "${UPDATE_VERSION:?UPDATE_VERSION is required}"
: "${UPDATE_BUILD:?UPDATE_BUILD is required}"
: "${DMG_PATH:?DMG_PATH is required}"
: "${GITHUB_DMG_URL:?GITHUB_DMG_URL is required}"

[[ -f "$DMG_PATH" ]] || { echo "DMG_PATH does not exist: $DMG_PATH" >&2; exit 1; }
[[ "$GITHUB_DMG_URL" == https://* ]] || { echo "GITHUB_DMG_URL must use HTTPS" >&2; exit 1; }
if [[ -n "${GITEE_DMG_URL:-}" && "$GITEE_DMG_URL" != https://* ]]; then
  echo "GITEE_DMG_URL must use HTTPS" >&2
  exit 1
fi

mkdir -p "$(dirname "$MANIFEST_PATH")"
if [[ "$(uname -s)" == "Darwin" ]]; then
  DMG_SIZE="$(/usr/bin/stat -f '%z' "$DMG_PATH")"
else
  DMG_SIZE="$(stat -c '%s' "$DMG_PATH")"
fi
if command -v shasum >/dev/null 2>&1; then
  DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
else
  DMG_SHA256="$(sha256sum "$DMG_PATH" | awk '{print $1}')"
fi
PUBLISHED_AT="${UPDATE_PUBLISHED_AT:-$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')}"
MINIMUM_SYSTEM_VERSION="${UPDATE_MINIMUM_SYSTEM_VERSION:-15.0}"
RELEASE_PAGE_URL="${UPDATE_RELEASE_PAGE_URL:-https://github.com/YangChen-cn/yuangui/releases/tag/v$UPDATE_VERSION}"
ZH_HIGHLIGHTS_JSON="${UPDATE_HIGHLIGHTS_ZH_JSON:-[]}"
EN_HIGHLIGHTS_JSON="${UPDATE_HIGHLIGHTS_EN_JSON:-[]}"

DMG_SIZE="$DMG_SIZE" DMG_SHA256="$DMG_SHA256" UPDATE_VERSION="$UPDATE_VERSION" \
UPDATE_BUILD="$UPDATE_BUILD" PUBLISHED_AT="$PUBLISHED_AT" \
MINIMUM_SYSTEM_VERSION="$MINIMUM_SYSTEM_VERSION" RELEASE_PAGE_URL="$RELEASE_PAGE_URL" \
GITHUB_DMG_URL="$GITHUB_DMG_URL" GITEE_DMG_URL="${GITEE_DMG_URL:-}" \
ZH_HIGHLIGHTS_JSON="$ZH_HIGHLIGHTS_JSON" EN_HIGHLIGHTS_JSON="$EN_HIGHLIGHTS_JSON" \
python3 - "$MANIFEST_PATH" <<'PY'
import json
import os
import re
import sys
from urllib.parse import urlparse

output = sys.argv[1]
version = os.environ["UPDATE_VERSION"]
build = int(os.environ["UPDATE_BUILD"])
if build <= 0 or not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)*(?:[-+][0-9A-Za-z.-]+)?", version):
    raise SystemExit("invalid version or build")

def https(value):
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.netloc)

if not https(os.environ["RELEASE_PAGE_URL"]):
    raise SystemExit("release page must use HTTPS")

size = int(os.environ["DMG_SIZE"])
sha256 = os.environ["DMG_SHA256"]
if size <= 0 or not re.fullmatch(r"[0-9a-f]{64}", sha256):
    raise SystemExit("invalid local DMG metadata")

assets = [{
    "provider": "github",
    "url": os.environ["GITHUB_DMG_URL"],
    "sha256": sha256,
    "size": size,
}]
gitee_url = os.environ.get("GITEE_DMG_URL", "")
if gitee_url:
    if not https(gitee_url):
        raise SystemExit("GITEE_DMG_URL must use HTTPS")
    assets.insert(0, {
        "provider": "gitee",
        "url": gitee_url,
        "sha256": sha256,
        "size": size,
    })

manifest = {
    "schemaVersion": 1,
    "version": version,
    "build": build,
    "minimumSystemVersion": os.environ["MINIMUM_SYSTEM_VERSION"],
    "publishedAt": os.environ["PUBLISHED_AT"],
    "releasePageURL": os.environ["RELEASE_PAGE_URL"],
    "highlights": {
        "zh-Hans": json.loads(os.environ["ZH_HIGHLIGHTS_JSON"]),
        "en": json.loads(os.environ["EN_HIGHLIGHTS_JSON"]),
    },
    "assets": assets,
}
with open(output, "w", encoding="utf-8", newline="\n") as handle:
    json.dump(manifest, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

UPDATE_MANIFEST_PATH="$MANIFEST_PATH" DMG_PATH="$DMG_PATH" \
"$ROOT_DIR/script/verify_update_manifest.sh"

echo "Manifest: $MANIFEST_PATH"
echo "Version: $UPDATE_VERSION"
echo "Build: $UPDATE_BUILD"
echo "Size: $DMG_SIZE"
echo "SHA-256: $DMG_SHA256"
