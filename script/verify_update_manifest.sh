#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH="${UPDATE_MANIFEST_PATH:-$ROOT_DIR/updates/latest.json}"

[[ -f "$MANIFEST_PATH" ]] || { echo "Manifest does not exist: $MANIFEST_PATH" >&2; exit 1; }

MANIFEST_PATH="$MANIFEST_PATH" DMG_PATH="${DMG_PATH:-}" python3 - <<'PY'
import json
import os
import re
from datetime import datetime
from urllib.parse import urlparse

path = os.environ["MANIFEST_PATH"]
with open(path, encoding="utf-8") as handle:
    manifest = json.load(handle)
if manifest.get("schemaVersion") != 1:
    raise SystemExit("unsupported schemaVersion")
if not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)*", manifest.get("version", "")):
    raise SystemExit("invalid version")
if not isinstance(manifest.get("build"), int) or manifest["build"] <= 0:
    raise SystemExit("invalid build")
if not isinstance(manifest.get("minimumSystemVersion"), str):
    raise SystemExit("invalid minimumSystemVersion")
if not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)*", manifest["minimumSystemVersion"]):
    raise SystemExit("invalid minimumSystemVersion")
published_at = manifest.get("publishedAt")
if not isinstance(published_at, str) or not published_at:
    raise SystemExit("missing publishedAt")
try:
    datetime.fromisoformat(published_at.replace("Z", "+00:00"))
except ValueError:
    raise SystemExit("invalid publishedAt")
release_page = manifest.get("releasePageURL")
if release_page:
    parsed_release_page = urlparse(release_page)
    if parsed_release_page.scheme != "https" or not parsed_release_page.netloc:
        raise SystemExit("releasePageURL must use HTTPS")
assets = manifest.get("assets") or []
if not assets:
    raise SystemExit("assets is empty")
identities = set()
for asset in assets:
    provider = asset.get("provider")
    if provider not in {"gitee", "github"}:
        raise SystemExit("unsupported asset provider")
    url = asset.get("url", "")
    parsed = urlparse(url)
    if parsed.scheme != "https" or not parsed.netloc:
        raise SystemExit("asset URL must use HTTPS")
    host = parsed.hostname.lower()
    if provider == "gitee" and not (host == "gitee.com" or host.endswith(".gitee.com")):
        raise SystemExit("Gitee asset URL does not match provider")
    if provider == "github" and host not in {"github.com", "objects.githubusercontent.com", "github-releases.githubusercontent.com"}:
        raise SystemExit("GitHub asset URL does not match provider")
    if not re.fullmatch(r"[0-9a-f]{64}", asset.get("sha256", "")):
        raise SystemExit("invalid SHA-256")
    if not isinstance(asset.get("size"), int) or asset["size"] <= 0:
        raise SystemExit("invalid asset size")
    identity = (asset.get("provider"), url)
    if identity in identities:
        raise SystemExit("duplicate asset")
    identities.add(identity)

dmg_path = os.environ.get("DMG_PATH", "")
if dmg_path:
    import hashlib
    actual_size = os.path.getsize(dmg_path)
    actual_hash = hashlib.sha256()
    with open(dmg_path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            actual_hash.update(chunk)
    actual_hash = actual_hash.hexdigest()
    if not any(a["size"] == actual_size and a["sha256"] == actual_hash for a in assets):
        raise SystemExit("local DMG does not match a manifest asset")
PY

echo "Manifest schema and asset validation passed: $MANIFEST_PATH"
