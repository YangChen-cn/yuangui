#!/bin/zsh
set -euo pipefail

# 从本机发布 DMG 到 Gitee。
#
# GitHub Actions 云端 runner 向 Gitee 上传大文件 multipart 会挂起（无响应
# 也无超时）；本机网络正常时 29MB 上传只需数秒。因此 Gitee DMG 上传改为
# 发布者在本地执行，workflow 只负责校验、manifest 与镜像同步。
#
# 资产生命周期（复用/去重/上传/校验）委托给 script/gitee_release_assets.sh，
# 与 GitHub Actions workflow 共用同一套实现，避免两套逻辑漂移。
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
SHARED="$script_dir/gitee_release_assets.sh"

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

# 1. 复用或创建 Gitee release（共享脚本对 404 容错，缺失时自动创建）
release_id="$(GITEE_OWNER="$GITEE_OWNER" GITEE_REPO="$GITEE_REPO" GITEE_TOKEN="$GITEE_TOKEN" \
  "$SHARED" ensure-release "$TAG" "YuanGUI $VERSION")"
print "Gitee release id=$release_id"

# 2. 上传并校验资产：保留一个字节一致的资产，删除所有同名重复，缺失才上传
printf '%s  %s\n' "$EXPECTED_SHA" "YuanGUI-$VERSION.dmg" > "$DMG.sha256"
GITEE_OWNER="$GITEE_OWNER" GITEE_REPO="$GITEE_REPO" GITEE_TOKEN="$GITEE_TOKEN" \
  "$SHARED" ensure-asset "$TAG" "$DMG" "$EXPECTED_SIZE" "$EXPECTED_SHA"
GITEE_OWNER="$GITEE_OWNER" GITEE_REPO="$GITEE_REPO" GITEE_TOKEN="$GITEE_TOKEN" \
  "$SHARED" ensure-asset "$TAG" "$DMG.sha256" \
  "$(stat -f '%z' "$DMG.sha256")" \
  "$(shasum -a 256 "$DMG.sha256" | awk '{print $1}')"

print "Done. Gitee release: $API/releases/$release_id"
