#!/bin/zsh
set -euo pipefail

# 一键发布稳定版本：
#   打包 DMG → 创建 GitHub Release（三资产）→ 本地上传 Gitee → 本地生成并
#   镜像 manifest → 验证两个 raw manifest。
#
# 所有涉及 Gitee 的步骤都在发布者本机执行（云 runner 连 Gitee 的大文件操作
# 会挂起）：DMG 上传走 publish_gitee_release.sh，manifest 生成与双端镜像走
# mirror_manifest_locally.sh。
#
# 前提（手动，机器不代做语义修改）：
#   - AppVersionInfo / build_and_run.sh / README / RELEASE_NOTES / About 高亮
#     已切换到目标版本并提交推送
#   - 仓库 secret GITEE_TOKEN 可创建 Gitee release
#
# 用法：
#   VERSION=2.8.1 BUILD=20 GITEE_TOKEN=xxx ./script/release.sh
#
# 脚本本身不修改任何源码或仓库配置；所有发布动作都是 gh/curl 调用。

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
GITEE_OWNER="yangchen716"
GITEE_REPO="yuangui"

: "${VERSION:?VERSION is required, for example VERSION=2.8.0}"
: "${BUILD:?BUILD is required, for example BUILD=19}"
: "${GITEE_TOKEN:?GITEE_TOKEN is required}"

TAG="v$VERSION"
DMG="$project_dir/dist/YuanGUI-$VERSION.dmg"

cd "$project_dir"

# 0. 前置检查：双语 release notes 必须含完整版本段；main 已推送且工作区
# 干净。任何有外部副作用的操作之前完成——否则会留下"Release 已公开、DMG
# 已上传但 manifest 未生成"的半发布状态，或打包未提交的本地代码。
for notes in RELEASE_NOTES.md RELEASE_NOTES.zh-CN.md; do
  grep -q "^## $VERSION " "$notes" || {
    print -u2 "missing version section '## $VERSION' in $notes"
    exit 1
  }
done

print "checking that main is pushed and the working tree is clean"
git fetch origin main
LOCAL_HEAD_SHA="$(git rev-parse HEAD)"
REMOTE_HEAD_SHA="$(git rev-parse origin/main)"
[[ "$LOCAL_HEAD_SHA" == "$REMOTE_HEAD_SHA" ]] || {
  print -u2 "local HEAD ($LOCAL_HEAD_SHA) differs from origin/main ($REMOTE_HEAD_SHA); commit and push first"
  exit 1
}
[[ -z "$(git status --porcelain)" ]] || {
  print -u2 "working tree is not clean; commit or stash first"
  exit 1
}

# 1. 打包 DMG（要求显式稳定 VERSION 与正 BUILD）
print "== 1/5 package_dmg.sh"
VERSION="$VERSION" BUILD="$BUILD" ./script/package_dmg.sh

# 2. 创建或补齐 GitHub Release（三资产：DMG + 双语 notes）
print "== 2/5 GitHub Release $TAG"
if gh release view "$TAG" >/dev/null 2>&1; then
  print "release exists; uploading missing assets"
  gh release upload "$TAG" "$DMG" RELEASE_NOTES.md RELEASE_NOTES.zh-CN.md --clobber
else
  BODY="$(mktemp)"
  awk "/^## $VERSION /{p=1} p&&/^## Earlier releases/{p=0} p" RELEASE_NOTES.md > "$BODY"
  printf '\nBuild: %s\n' "$BUILD" >> "$BODY"
  gh release create "$TAG" "$DMG" RELEASE_NOTES.md RELEASE_NOTES.zh-CN.md \
    --title "YuanGUI $VERSION" --notes-file "$BODY"
  rm -f "$BODY"
fi

# 3. 从本机上传 DMG + sidecar 到 Gitee（云 runner 上传会挂起）
print "== 3/5 publish to Gitee"
VERSION="$VERSION" BUILD="$BUILD" GITEE_TOKEN="$GITEE_TOKEN" \
  ./script/publish_gitee_release.sh

# 4. 本地生成并镜像 manifest：Gitee 资产字节校验、双语高亮提取、防回退守卫、
# manifest 生成/校验、提交推送 GitHub main、Gitee contents API 写入并轮询 raw
# 一致。云 runner 连 Gitee 的大文件验证会挂起，全部步骤在发布者本机完成。
print "== 4/5 mirror manifest locally"
VERSION="$VERSION" BUILD="$BUILD" GITEE_TOKEN="$GITEE_TOKEN" \
  ./script/mirror_manifest_locally.sh

# 5. 验证两个 raw manifest 与 Gitee DMG
print "== 5/5 verify raw manifests"
for url in \
  "https://raw.githubusercontent.com/YangChen-cn/yuangui/main/updates/latest.json" \
  "https://gitee.com/$GITEE_OWNER/$GITEE_REPO/raw/main/updates/latest.json"; do
  body="$(curl -sfL --max-time 60 "$url")"
  version="$(print -r -- "$body" | jq -r '.version')"
  build="$(print -r -- "$body" | jq -r '.build')"
  [[ "$version" == "$VERSION" && "$build" == "$BUILD" ]] || {
    print -u2 "manifest mismatch at $url: got $version/$build"
    exit 1
  }
  print "ok: $url ($version/$build)"
done

print "Release $VERSION ($BUILD) published and mirrored."
