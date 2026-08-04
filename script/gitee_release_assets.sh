#!/bin/bash
set -euo pipefail

# Shared Gitee release-asset handling, used by BOTH the local publish script
# (script/publish_gitee_release.sh) and the GitHub Actions mirror workflow
# (.github/workflows/mirror-release-to-gitee.yml). One implementation means
# the duplicate-name cleanup and byte-identical verification cannot drift
# between the two call sites.
#
# Gitee allows duplicate asset names, and its release-detail API omits asset
# ids, so all reads and deletes go through the attach_files endpoint which
# carries id + size.
#
# Environment: GITEE_OWNER, GITEE_REPO, GITEE_TOKEN
#
# Commands:
#   release-id TAG                      echo the release id, or "" when the
#                                       release does not exist (404-tolerant)
#   ensure-release TAG NAME [BODY] [PRERELEASE]
#                                       create the release when missing and
#                                       echo its id
#   list-assets TAG                     JSON array of every attachment
#                                       (id, name, browser_download_url)
#   ensure-asset TAG FILE SHA256 SIZE   keep exactly one byte-identical asset
#                                       for the file's name (delete every other
#                                       same-name duplicate, including any
#                                       correct extra copies), upload when none
#                                       matches (3 rounds), then verify

GITEE_OWNER="${GITEE_OWNER:?GITEE_OWNER is required}"
GITEE_REPO="${GITEE_REPO:?GITEE_REPO is required}"
GITEE_TOKEN="${GITEE_TOKEN:?GITEE_TOKEN is required}"
API="https://gitee.com/api/v5/repos/$GITEE_OWNER/$GITEE_REPO"

# curl GET that treats a missing resource as an empty answer instead of an
# errexit abort. Only a malformed response (no JSON id) yields "".
release_id_for_tag() {
  local tag="$1"
  curl --silent --show-error \
    --connect-timeout 15 --max-time 60 \
    "$API/releases/tags/$tag?access_token=$GITEE_TOKEN" \
    | jq -r '.id // empty' 2>/dev/null || true
}

# "id<TAB>url" lines for every asset whose name matches; empty when the
# release is missing or has no such asset.
same_name_assets() {
  local tag="$1" name="$2" release_id
  release_id="$(release_id_for_tag "$tag")"
  [[ -n "$release_id" ]] || return 0
  curl --silent --show-error --fail \
    --connect-timeout 15 --max-time 60 \
    "$API/releases/$release_id/attach_files?access_token=$GITEE_TOKEN" \
    | jq -r --arg name "$name" \
      '.[] | select(.name == $name) | "\(.id)\t\(.browser_download_url // .url // "")"' \
    || true
}

# Full JSON array of every attachment (id, name, browser_download_url); "[]"
# when the release is missing.
list_assets() {
  local tag="$1" release_id
  release_id="$(release_id_for_tag "$tag")"
  [[ -n "$release_id" ]] || { echo "[]"; return 0; }
  curl --silent --show-error --fail \
    --connect-timeout 15 --max-time 60 \
    "$API/releases/$release_id/attach_files?access_token=$GITEE_TOKEN" \
    || true
}

asset_matches() {
  local url="$1" expected_size="$2" expected_sha="$3"
  local tmp actual_size actual_sha
  tmp="$(mktemp)"
  if ! curl --silent --show-error --fail --location \
    --connect-timeout 20 --max-time 300 \
    "$url" --output "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  actual_size="$(stat -f '%z' "$tmp" 2>/dev/null || stat -c '%s' "$tmp")"
  # Note the parentheses: `a || b | awk` would parse as `a || (b | awk)` and
  # leave the full "hash  filename" in the variable on the first branch.
  actual_sha="$((shasum -a 256 "$tmp" 2>/dev/null || sha256sum "$tmp") | awk '{print $1}')"
  rm -f "$tmp"
  [[ "$actual_size" == "$expected_size" && "$actual_sha" == "$expected_sha" ]]
}

# The core idempotent operation: keep the first byte-identical asset, delete
# every other same-name asset (stale duplicates AND extra correct copies —
# Gitee allows duplicate names, and readers may pick the first entry).
ensure_asset() {
  local tag="$1" file="$2" expected_size="$3" expected_sha="$4"
  local name release_id kept id url attempt
  name="$(basename "$file")"
  release_id="$(release_id_for_tag "$tag")"
  [[ -n "$release_id" ]] || {
    echo "Gitee release $tag does not exist" >&2
    return 1
  }

  for attempt in 1 2 3; do
    kept=""
    while IFS=$'\t' read -r id url; do
      [[ -n "$id" ]] || continue
      if [[ -z "$kept" && -n "$url" ]] && asset_matches "$url" "$expected_size" "$expected_sha"; then
        kept="$id"
        echo "Gitee asset verified: $name (id=$id)"
        continue
      fi
      echo "Removing duplicate Gitee asset: $name (id=$id)"
      curl --silent --show-error --fail \
        --connect-timeout 15 --max-time 60 \
        --request DELETE \
        --data-urlencode "access_token=$GITEE_TOKEN" \
        "$API/releases/$release_id/attach_files/$id" >/dev/null || true
    done <<< "$(same_name_assets "$tag" "$name")"

    [[ -n "$kept" ]] && return 0

    echo "Uploading $name (attempt $attempt/3)"
    if curl --silent --show-error --fail \
      --connect-timeout 20 --max-time 300 \
      --request POST \
      --form "access_token=$GITEE_TOKEN" \
      --form "file=@$file" \
      "$API/releases/$release_id/attach_files" >/dev/null; then
      # The upload may have been stored even when the response was lost; the
      # next round re-lists and verifies instead of uploading again blindly.
      continue
    fi
    if [[ "$attempt" -lt 3 ]]; then
      sleep $((attempt * 20))
    fi
  done

  echo "Unable to upload and verify Gitee asset $name after 3 attempts" >&2
  return 1
}

ensure_release() {
  local tag="$1" name="$2" body="${3:-}" prerelease="${4:-false}"
  local release_id
  release_id="$(release_id_for_tag "$tag")"
  if [[ -n "$release_id" ]]; then
    echo "$release_id"
    return 0
  fi
  echo "Creating Gitee release $tag"
  curl --silent --show-error --fail \
    --connect-timeout 15 --max-time 60 \
    --request POST \
    --data-urlencode "access_token=$GITEE_TOKEN" \
    --data-urlencode "tag_name=$tag" \
    --data-urlencode "name=$name" \
    --data-urlencode "body=$body" \
    --data-urlencode "prerelease=$prerelease" \
    "$API/releases" | jq -r '.id'
}

command="$1"; shift
case "$command" in
  release-id)
    release_id_for_tag "$1"
    ;;
  ensure-release)
    ensure_release "$1" "$2" "${3:-}" "${4:-false}"
    ;;
  list-assets)
    list_assets "$1"
    ;;
  ensure-asset)
    ensure_asset "$1" "$2" "$3" "$4"
    ;;
  *)
    echo "Unknown command: $command" >&2
    echo "usage: gitee_release_assets.sh <release-id|ensure-release|list-assets|ensure-asset> ..." >&2
    exit 1
    ;;
esac
