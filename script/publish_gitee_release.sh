#!/bin/zsh
set -euo pipefail

# 从本机发布 DMG 到 Gitee。
#
# GitHub Actions 云端 runner 向 Gitee 上传大文件 multipart 会挂起（无响应
# 也无超时）；本机网络正常时 29MB 上传只需数秒。因此 Gitee DMG 上传改为
# 发布者在本地执行，workflow 只负责校验、manifest 与镜像同步。
#
# 用法：
#   VERSION=2.8.0 BUILD=19 GITEE_TOKEN=xxx ./script/publish_gitee_release.sh
#
# 之后在 GitHub Actions 手动运行 mirror-release-to-gitee.yml（tag=v2.8.0
# build=19），workflow 会复用这里上传的资产并生成 manifest。

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
GITEE_OWNER="yangchen716"
GITEE_REPO="yuangui"
API="https://gitee.com/api/v5/repos/$GITEE_OWNER/$GITEE_REPO"

: "${VERSION:?VERSION is required, for example VERSION=2.8.0}"
: "${BUILD:?BUILD is required, for example BUILD=19}"
: "${GITEE_TOKEN:?GITEE_TOKEN is required}"

DMG="$project_dir/dist/YuanGUI-$VERSION.dmg"
[[ -f "$DMG" ]] || {
  print -u2 "missing $DMG; run ./script/package_dmg.sh first"
  exit 1
}
TAG="v$VERSION"

cd "$project_dir"

EXPECTED_SIZE="$(stat -f '%z' "$DMG")"
EXPECTED_SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

gitee_get() {
  curl --silent --show-error --fail \
    --connect-timeout 15 --max-time 60 \
    "$API/$1"
}

# 1. 复用或创建 Gitee release
release_id="$(gitee_get "releases/tags/$TAG?access_token=$GITEE_TOKEN" | jq -r '.id // empty')"
if [[ -z "$release_id" ]]; then
  print "Creating Gitee release $TAG"
  release_id="$(curl --silent --show-error --fail \
    --connect-timeout 15 --max-time 60 \
    --request POST \
    --data-urlencode "access_token=$GITEE_TOKEN" \
    --data-urlencode "tag_name=$TAG" \
    --data-urlencode "name=YuanGUI $VERSION" \
    "$API/releases" | jq -r '.id')"
fi
print "Gitee release id=$release_id"

# 2. 上传并校验一个资产；已存在且字节匹配则复用，绝不重复上传。
asset_exists_and_matches() {
  local name="$1" expected_size="$2" expected_sha="$3"
  local url tmp actual_size actual_sha
  url="$(gitee_get "releases/$release_id?access_token=$GITEE_TOKEN" | \
    jq -r --arg name "$name" '(.assets // [])[] | select(.name == $name) | (.browser_download_url // .url // empty)' | \
    head -n 1)"
  [[ -n "$url" ]] || return 1
  tmp="$(mktemp)"
  curl --silent --show-error --fail --location \
    --connect-timeout 20 --max-time 300 \
    "$url" --output "$tmp" || { rm -f "$tmp"; return 1 }
  actual_size="$(stat -f '%z' "$tmp")"
  actual_sha="$(shasum -a 256 "$tmp" | awk '{print $1}')"
  rm -f "$tmp"
  [[ "$actual_size" == "$expected_size" && "$actual_sha" == "$expected_sha" ]]
}


remove_asset() {
  local name="$1" id
  id="$(gitee_get "releases/$release_id?access_token=$GITEE_TOKEN" | \
    jq -r --arg name "$name" '(.assets // [])[] | select(.name == $name) | .id // empty' | \
    head -n 1)"
  [[ -n "$id" ]] || return 0
  print "Removing stale Gitee asset $name"
  curl --silent --show-error --fail \
    --connect-timeout 15 --max-time 60 \
    --request DELETE \
    --data-urlencode "access_token=$GITEE_TOKEN" \
    "$API/releases/$release_id/attach_files/$id" >/dev/null
}

upload_with_verify() {
  local file="$1" expected_size="$2" expected_sha="$3"
  local name
  name="${file:t}"
  for attempt in 1 2 3; do
    if asset_exists_and_matches "$name" "$expected_size" "$expected_sha"; then
      print "Gitee asset already matches: $name"
      return 0
    fi
    remove_asset "$name" || true
    print "Uploading $name (attempt $attempt/3)"
    if curl --silent --show-error --fail \
      --connect-timeout 20 --max-time 300 \
      --request POST \
      --form "access_token=$GITEE_TOKEN" \
      --form "file=@$file" \
      "$API/releases/$release_id/attach_files" >/dev/null; then
      if asset_exists_and_matches "$name" "$expected_size" "$expected_sha"; then
        print "Uploaded and verified: $name"
        return 0
      fi
    fi
    [[ "$attempt" -lt 3 ]] && sleep $((attempt * 20))
  done
  print -u2 "Unable to upload and verify $name after 3 attempts"
  return 1
}

# 3. 与 workflow 相同的 sidecar 格式： "<sha>  <asset name>"
printf '%s  %s\n' "$EXPECTED_SHA" "YuanGUI-$VERSION.dmg" > "$DMG.sha256"
upload_with_verify "$DMG" "$EXPECTED_SIZE" "$EXPECTED_SHA"
upload_with_verify "$DMG.sha256" \
  "$(stat -f '%z' "$DMG.sha256")" \
  "$(shasum -a 256 "$DMG.sha256" | awk '{print $1}')"

print "Done. Gitee release: $API/releases/$release_id"
