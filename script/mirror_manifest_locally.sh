#!/bin/zsh
set -euo pipefail

# 在发布者本机完成 manifest 生成与双端镜像，替代 mirror-release-to-gitee.yml
# 的云 runner job。云 runner 访问 Gitee 的 CDN 大文件验证下载会挂起（与 multipart
# 上传挂起同源），而本机网络对 Gitee 是可靠的；本脚本把 workflow 里所有涉及
# Gitee 大文件的步骤搬到本地，其余步骤（高亮提取、manifest 生成、commit、
# contents API 写小文件）本地同样能做。
#
# 步骤：
#   解析 GitHub Release 元数据（prerelease / published_at / 唯一 DMG / 双语 notes）
#   → 用 GitHub API digest 校验本机 DMG 与发布资产同字节（不下载）
#   → 复用并校验 Gitee DMG 与 .sha256 sidecar（共享资产脚本，本机网络）
#   → 下载 Gitee DMG 验证字节一致（云上会挂的步骤，本机秒级）
#   → 从两份 RELEASE_NOTES 提取双语高亮（与旧 workflow 相同的提取逻辑）
#   → 防回退守卫，生成并校验 updates/latest.json
#   → 提交并推送 GitHub main
#   → 经 Gitee contents API 写入该文件，轮询 raw 直到字节一致
#
# 用法：
#   VERSION=2.8.1 BUILD=20 GITEE_TOKEN=xxx ./script/mirror_manifest_locally.sh
# 可选：MINIMUM_SYSTEM_VERSION（默认 15.0）、ALLOW_ROLLBACK=true（有意回退时）。
#
# 脚本不修改任何源码；唯一仓库改动是提交生成的 updates/latest.json。

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
GITEE_OWNER="yangchen716"
GITEE_REPO="yuangui"
SHARED="$script_dir/gitee_release_assets.sh"
GITEE_API="https://gitee.com/api/v5/repos/$GITEE_OWNER/$GITEE_REPO"
GITEE_RAW_URL="https://gitee.com/$GITEE_OWNER/$GITEE_REPO/raw/main/updates/latest.json"

: "${VERSION:?VERSION is required, for example VERSION=2.8.1}"
: "${BUILD:?BUILD is required, for example BUILD=20}"
: "${GITEE_TOKEN:?GITEE_TOKEN is required}"
MINIMUM_SYSTEM_VERSION="${MINIMUM_SYSTEM_VERSION:-15.0}"
ALLOW_ROLLBACK="${ALLOW_ROLLBACK:-false}"

TAG="v$VERSION"
DMG="$project_dir/dist/YuanGUI-$VERSION.dmg"
[[ -f "$DMG" ]] || {
  print -u2 "missing $DMG; run ./script/package_dmg.sh first"
  exit 1
}
[[ "$BUILD" =~ ^[1-9][0-9]*$ ]] || {
  print -u2 "a positive build number is required"
  exit 1
}

cd "$project_dir"

cleanup() {
  for file in "$RELEASE_JSON" "$GITEE_DMG" "$ZH_JSON" "$EN_JSON" "$RAW_FILE" "$FILE_INFO"; do
    [[ -n "${file:-}" && -f "$file" ]] && rm -f "$file"
  done
}
trap cleanup EXIT

# 1. 解析并校验 GitHub Release 元数据
print "== resolving GitHub Release $TAG"
RELEASE_JSON="$(mktemp)"
gh api "repos/YangChen-cn/yuangui/releases/tags/$TAG" > "$RELEASE_JSON"
jq -e '.prerelease == false' "$RELEASE_JSON" >/dev/null || {
  print -u2 "stable update channel refuses prerelease Releases: $TAG"
  exit 1
}
PUBLISHED_AT="$(jq -r '.published_at // empty' "$RELEASE_JSON")"
[[ -n "$PUBLISHED_AT" ]] || {
  print -u2 "GitHub Release $TAG has no publication timestamp"
  exit 1
}

DMG_COUNT="$(jq '[.assets[] | select(.name | test("^YuanGUI-.*\\.dmg$"; "i"))] | length' "$RELEASE_JSON")"
[[ "$DMG_COUNT" == "1" ]] || {
  print -u2 "expected exactly one YuanGUI-*.dmg, found $DMG_COUNT"
  exit 1
}
ASSET_NAME="$(jq -r '[.assets[] | select(.name | test("^YuanGUI-.*\\.dmg$"; "i"))][0].name' "$RELEASE_JSON")"
for notes_name in RELEASE_NOTES.md RELEASE_NOTES.zh-CN.md; do
  jq -e --arg name "$notes_name" '.assets[] | select(.name == $name)' "$RELEASE_JSON" >/dev/null 2>&1 || {
    print -u2 "GitHub Release $TAG must include $notes_name"
    exit 1
  }
done

# 2. 本机 DMG 与 GitHub 资产同字节（GitHub API 的资产 digest 即可，不必下载）
LOCAL_SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
LOCAL_SIZE="$(stat -f '%z' "$DMG")"
GITHUB_DIGEST="$(jq -r --arg name "$ASSET_NAME" '.assets[] | select(.name == $name) | .digest // empty' "$RELEASE_JSON")"
if [[ -n "$GITHUB_DIGEST" ]]; then
  [[ "${GITHUB_DIGEST#sha256:}" == "$LOCAL_SHA" ]] || {
    print -u2 "GitHub asset digest ${GITHUB_DIGEST#sha256:} differs from the local DMG $LOCAL_SHA"
    exit 1
  }
else
  print -u2 "GitHub asset digest missing; uploading the local DMG to the release first"
  exit 1
fi
print "local DMG matches the GitHub asset: $LOCAL_SHA"

# 3. 复用并校验 Gitee DMG 与 sidecar（本机网络；本地发布脚本通常已上传）
print "== reconciling Gitee assets"
printf '%s  %s\n' "$LOCAL_SHA" "$ASSET_NAME" > "$DMG.sha256"
GITEE_OWNER="$GITEE_OWNER" GITEE_REPO="$GITEE_REPO" GITEE_TOKEN="$GITEE_TOKEN" \
  "$SHARED" ensure-asset "$TAG" "$DMG" "$LOCAL_SIZE" "$LOCAL_SHA"
GITEE_OWNER="$GITEE_OWNER" GITEE_REPO="$GITEE_REPO" GITEE_TOKEN="$GITEE_TOKEN" \
  "$SHARED" ensure-asset "$TAG" "$DMG.sha256" \
  "$(stat -f '%z' "$DMG.sha256")" \
  "$(shasum -a 256 "$DMG.sha256" | awk '{print $1}')"

# 4. 下载 Gitee DMG 并验证字节一致（云 runner 上这一步会挂起；本机网络秒级）
GITEE_DMG_URL="$(GITEE_OWNER="$GITEE_OWNER" GITEE_REPO="$GITEE_REPO" GITEE_TOKEN="$GITEE_TOKEN" \
  "$SHARED" list-assets "$TAG" | jq -r --arg name "$ASSET_NAME" \
    '.[] | select(.name == $name) | (.browser_download_url // .url // empty)' | head -n 1)"
[[ "$GITEE_DMG_URL" == https://gitee.com/* ]] || {
  print -u2 "Gitee did not return a usable HTTPS DMG URL"
  exit 1
}
GITEE_DMG="$(mktemp)"
curl --silent --show-error --fail --location --retry 3 \
  --connect-timeout 20 --max-time 1200 \
  "$GITEE_DMG_URL" --output "$GITEE_DMG"
[[ "$(stat -f '%z' "$GITEE_DMG")" == "$LOCAL_SIZE" ]] || {
  print -u2 "Gitee DMG size differs from the local DMG"
  exit 1
}
[[ "$(shasum -a 256 "$GITEE_DMG" | awk '{print $1}')" == "$LOCAL_SHA" ]] || {
  print -u2 "Gitee DMG SHA-256 differs from the local DMG"
  exit 1
}
print "Gitee DMG verified: $LOCAL_SIZE bytes, $LOCAL_SHA"

# 5. 从两份 RELEASE_NOTES 提取双语高亮（与旧 workflow 相同的提取逻辑）
ZH_JSON="$(mktemp)"
EN_JSON="$(mktemp)"
python3 - "$ZH_JSON" "$EN_JSON" <<'PY'
import json
import os
import re
import sys

zh_path, en_path = sys.argv[1], sys.argv[2]


def clean(line):
    line = re.sub(r"^\s*(?:[-*+]\s+|\d+[.)]\s+)", "", line.strip())
    line = re.sub(r"[`*_#]", "", line)
    line = re.sub(r"\s+", " ", line).strip()
    if not line:
        return None
    if len(line) <= 120:
        return line
    shortened = line[:119].rstrip()
    if re.search(r"[A-Za-z]", shortened):
        word_boundary = shortened.rsplit(" ", 1)[0].rstrip()
        if len(word_boundary) >= 40:
            shortened = word_boundary
    return shortened + "…"


def bullets(text):
    values = []
    for line in text.splitlines():
        if re.match(r"^\s*(?:[-*+]\s+|\d+[.)]\s+)", line):
            value = clean(line)
            if value and value not in values:
                values.append(value)
        if len(values) == 2:
            break
    return values


def extract(path):
    with open(path, encoding="utf-8") as handle:
        return bullets(handle.read())


zh = extract("RELEASE_NOTES.zh-CN.md")
en = extract("RELEASE_NOTES.md")
with open(zh_path, "w", encoding="utf-8") as handle:
    json.dump(zh, handle, ensure_ascii=False, separators=(",", ":"))
with open(en_path, "w", encoding="utf-8") as handle:
    json.dump(en, handle, ensure_ascii=False, separators=(",", ":"))
PY
print "highlights extracted: zh=$(cat "$ZH_JSON") en=$(cat "$EN_JSON")"

# 6. 防回退守卫：无显式 allow_rollback 时拒绝低于当前稳定版的版本
if [[ "$ALLOW_ROLLBACK" != "true" ]]; then
  CURRENT_VERSION="$(jq -r '.version' updates/latest.json)"
  python3 - "$CURRENT_VERSION" "$VERSION" <<'PY'
import os
import sys


def version_key(value):
    parts = [int(part) for part in value.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))


current, candidate = sys.argv[1], sys.argv[2]
if version_key(candidate) < version_key(current):
    raise SystemExit(
        f"Refusing to publish lower stable version {candidate}; current manifest is {current}. "
        "Use ALLOW_ROLLBACK=true only for an intentional rollback."
    )
PY
fi

# 7. 生成并校验 manifest
print "== generating updates/latest.json"
UPDATE_VERSION="$VERSION" UPDATE_BUILD="$BUILD" DMG_PATH="$DMG" \
  GITHUB_DMG_URL="https://github.com/YangChen-cn/yuangui/releases/download/$TAG/$ASSET_NAME" \
  GITEE_DMG_URL="$GITEE_DMG_URL" \
  UPDATE_RELEASE_PAGE_URL="https://github.com/YangChen-cn/yuangui/releases/tag/$TAG" \
  UPDATE_PUBLISHED_AT="$PUBLISHED_AT" \
  UPDATE_MINIMUM_SYSTEM_VERSION="$MINIMUM_SYSTEM_VERSION" \
  UPDATE_HIGHLIGHTS_ZH_JSON="$(cat "$ZH_JSON")" \
  UPDATE_HIGHLIGHTS_EN_JSON="$(cat "$EN_JSON")" \
  ./script/generate_update_manifest.sh
UPDATE_MANIFEST_PATH="$project_dir/updates/latest.json" DMG_PATH="$DMG" \
  ./script/verify_update_manifest.sh

# 8. 提交并推送 GitHub main。commit message 带 [skip-gitee-sync] 标记：push
# 触发的 sync-manifest workflow 会跳过这次提交（Gitee 已由本脚本写好），
# 避免本地 contents API 写入与 Actions 的写入竞争同一个 Gitee 文件 SHA。
# 只有人工手动修改 updates/latest.json 的提交（不带标记）才由 workflow 同步。
print "== committing updates/latest.json to GitHub main"
git add updates/latest.json
if git diff --cached --quiet; then
  print "updates/latest.json is already current"
else
  git commit -m "Publish update manifest for $VERSION [skip-gitee-sync]"
  git push origin HEAD:main
fi

# 9. 经 Gitee contents API 写入（小文件，本机可靠），并轮询 raw 直到字节一致
print "== publishing updates/latest.json to Gitee"
EXPECTED_SHA="$(shasum -a 256 updates/latest.json | awk '{print $1}')"
RAW_FILE="$(mktemp)"
FILE_INFO="$(mktemp)"

raw_matches() {
  local phase="$1" attempt="$2" http_code curl_status actual_sha
  set +e
  http_code="$(curl --silent --show-error --location \
    --header 'Cache-Control: no-cache' \
    --connect-timeout 15 --max-time 60 \
    --output "$RAW_FILE" \
    --write-out '%{http_code}' \
    "$GITEE_RAW_URL")"
  curl_status=$?
  set -e
  actual_sha=""
  if [[ "$curl_status" -eq 0 && "$http_code" =~ ^2[0-9][0-9]$ && -s "$RAW_FILE" ]]; then
    actual_sha="$(shasum -a 256 "$RAW_FILE" | awk '{print $1}')"
  fi
  if [[ "$actual_sha" == "$EXPECTED_SHA" ]]; then
    print "Gitee raw manifest verified: phase=$phase attempt=$attempt http=$http_code sha256=$actual_sha"
    return 0
  fi
  print -u2 "Gitee raw manifest pending: phase=$phase attempt=$attempt curl_exit=$curl_status http=${http_code:-000} expected_sha=$EXPECTED_SHA actual_sha=${actual_sha:-unavailable}"
  return 1
}

poll_raw() {
  local phase="$1" attempts="$2" delay="$3" attempt
  for attempt in {1..$attempts}; do
    if raw_matches "$phase" "$attempt"; then
      return 0
    fi
    if [[ "$attempt" -lt "$attempts" ]]; then
      sleep "$delay"
    fi
  done
  return 1
}

if ! raw_matches initial 1; then
  FILE_HTTP="$(curl --silent --show-error \
    --connect-timeout 15 --max-time 120 \
    --output "$FILE_INFO" \
    --write-out '%{http_code}' \
    "$GITEE_API/contents/updates/latest.json?ref=main")"
  FILE_SHA=""
  if [[ "$FILE_HTTP" =~ ^2[0-9][0-9]$ ]]; then
    FILE_SHA="$(jq -r '.sha // empty' "$FILE_INFO")"
  fi
  CONTENT="$(base64 < updates/latest.json | tr -d '\n')"
  if [[ -n "$FILE_SHA" ]]; then
    print "publishing Gitee manifest through contents API: method=PUT"
    curl --silent --show-error --fail-with-body \
      --connect-timeout 15 --max-time 120 \
      --request PUT \
      --data-urlencode "access_token=$GITEE_TOKEN" \
      --data-urlencode "content=$CONTENT" \
      --data-urlencode "message=Publish update manifest for $VERSION" \
      --data-urlencode "branch=main" \
      --data-urlencode "sha=$FILE_SHA" \
      "$GITEE_API/contents/updates/latest.json" >/dev/null
  else
    print "publishing Gitee manifest through contents API: method=POST"
    curl --silent --show-error --fail-with-body \
      --connect-timeout 15 --max-time 120 \
      --request POST \
      --data-urlencode "access_token=$GITEE_TOKEN" \
      --data-urlencode "content=$CONTENT" \
      --data-urlencode "message=Create update manifest" \
      --data-urlencode "branch=main" \
      "$GITEE_API/contents/updates/latest.json" >/dev/null
  fi
  poll_raw contents 12 10 || {
    print -u2 "Gitee raw manifest was not created or does not match GitHub"
    exit 1
  }
fi
print "Gitee manifest: $GITEE_RAW_URL"
