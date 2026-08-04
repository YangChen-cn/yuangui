#!/bin/zsh
set -euo pipefail

# 一键发布稳定版本：
#   打包 DMG → 创建 GitHub Release（三资产）→ 本地上传 Gitee → dispatch 镜像
#   workflow → 等待完成 → 验证两个 raw manifest。
#
# 前提（手动，机器不代做语义修改）：
#   - AppVersionInfo / build_and_run.sh / README / RELEASE_NOTES / About 高亮
#     已切换到目标版本并提交推送
#   - 仓库 secret GITEE_TOKEN 可创建 Gitee release
#
# 用法：
#   VERSION=2.8.0 BUILD=19 GITEE_TOKEN=xxx ./script/release.sh
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

# 0. 前置检查：双语 release notes 必须含完整版本段
for notes in RELEASE_NOTES.md RELEASE_NOTES.zh-CN.md; do
  grep -q "^## $VERSION " "$notes" || {
    print -u2 "missing version section '## $VERSION' in $notes"
    exit 1
  }
done

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

# 4. dispatch 镜像 workflow（复用已上传资产，生成并镜像 manifest）
# 先记录 dispatch 前的基准（时间 / main HEAD / 已有最大 run id），之后只
# 接受 createdAt >= 基准时间、headSha 匹配且不是旧 run 的 workflow_dispatch
# run，避免新 run 尚未出现在列表时误抓上一次 dispatch。
print "== 4/5 dispatch mirror workflow"
DISPATCH_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EXPECTED_HEAD_SHA="$(git rev-parse HEAD)"
OLD_MAX_RUN_ID="$(gh run list --workflow mirror-release-to-gitee.yml --limit 1 \
  --json databaseId --jq '.[0].databaseId // 0' 2>/dev/null || print 0)"

gh workflow run mirror-release-to-gitee.yml \
  -f tag="$TAG" -f build="$BUILD" -f minimum_system_version=15.0

RUN_ID=""
for _ in {1..30}; do
  sleep 5
  RUN_ID="$(gh run list --workflow mirror-release-to-gitee.yml --limit 30 \
    --json databaseId,event,createdAt,headSha 2>/dev/null \
    | jq -r --arg started "$DISPATCH_STARTED" --arg sha "$EXPECTED_HEAD_SHA" --arg old "$OLD_MAX_RUN_ID" \
      '.[] | select(.event=="workflow_dispatch") | select(.createdAt >= $started) | select(.headSha == $sha) | select(.databaseId|tostring != $old) | .databaseId' \
    | head -n 1 || true)"
  [[ -n "$RUN_ID" ]] && break
done
[[ -n "$RUN_ID" ]] || { print -u2 "could not find the dispatched workflow run"; exit 1 }
print "waiting for run $RUN_ID"
gh run watch "$RUN_ID" --exit-status

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
