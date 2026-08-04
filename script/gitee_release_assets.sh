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
# Output convention: stdout carries ONLY machine-readable results; logs and
# diagnostics go to stderr.
#
# Environment: GITEE_OWNER, GITEE_REPO, GITEE_TOKEN
#
# Commands:
#   release-id TAG                      echo the release id, or nothing when
#                                       the release does not exist (HTTP 404
#                                       only); any other failure is an error
#   ensure-release TAG NAME [BODY] [PRERELEASE]
#                                       create the release only when it is
#                                       missing, and echo its id
#   list-assets TAG                     JSON array of every attachment
#                                       (id, name, browser_download_url)
#   ensure-asset TAG FILE SIZE SHA256   keep exactly one byte-identical asset
#                                       for the file's name (delete every other
#                                       same-name duplicate, including extra
#                                       correct copies), upload only when none
#                                       matches (3 rounds), and always finish
#                                       with a re-listed, re-verified,
#                                       exactly-one state

GITEE_OWNER="${GITEE_OWNER:?GITEE_OWNER is required}"
GITEE_REPO="${GITEE_REPO:?GITEE_REPO is required}"
GITEE_TOKEN="${GITEE_TOKEN:?GITEE_TOKEN is required}"
API="https://gitee.com/api/v5/repos/$GITEE_OWNER/$GITEE_REPO"

# Release lookup with explicit status handling: 200 parses the id, a missing
# release means "does not exist" (the caller may create), and any other
# status or a network failure is an error — never guess "missing" from a
# failure. Note that Gitee signals a missing tag with HTTP 200 and a `null`
# body rather than 404, so a 200 without an id is the missing case; a 200
# whose body is not valid JSON is still an error.
release_id_for_tag() {
  local tag="$1" body status
  body="$(curl --silent --show-error \
    --connect-timeout 15 --max-time 60 \
    --write-out '\n%{http_code}' \
    "$API/releases/tags/$tag?access_token=$GITEE_TOKEN")" || {
    echo "Gitee release lookup failed (network error): $tag" >&2
    return 1
  }
  status="${body##*$'\n'}"
  body="${body%$'\n'*}"
  case "$status" in
    200)
      local json_type id
      json_type="$(echo "$body" | jq -r 'type' 2>/dev/null)" || {
        echo "Gitee release lookup returned malformed JSON: $tag" >&2
        return 1
      }
      # Only a literal `null` body means "does not exist" (the caller may
      # create). Any other JSON without a valid id is an unexpected response
      # and must fail, not be guessed as missing.
      if [[ "$json_type" == "null" ]]; then
        return 0
      fi
      id="$(echo "$body" | jq -er '
        select(type == "object")
        | .id
        | select(type == "number" or type == "string")
      ' 2>/dev/null)" || {
        echo "Gitee release lookup returned an unexpected response: $tag" >&2
        return 1
      }
      echo "$id"
      ;;
    *)
      echo "Gitee release lookup failed (HTTP $status): $tag" >&2
      return 1
      ;;
  esac
}

# Full JSON array of every attachment, or "id<TAB>url" lines filtered to NAME
# when NAME is non-empty.
assets_for_release() {
  local release_id="$1" name="$2" json
  json="$(curl --silent --show-error --fail \
    --connect-timeout 15 --max-time 60 \
    "$API/releases/$release_id/attach_files?access_token=$GITEE_TOKEN")" || {
    echo "Gitee asset listing failed (release $release_id)" >&2
    return 1
  }
  if [[ -n "$name" ]]; then
    echo "$json" | jq -r --arg name "$name" \
      '.[] | select(.name == $name) | "\(.id)\t\(.browser_download_url // .url // "")"'
  else
    echo "$json"
  fi
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

# Keep exactly one byte-identical asset for NAME and delete every other
# same-name asset. Exit status:
#   0  exactly one byte-identical asset remains (re-listed and re-verified)
#   1  no asset with this name remains — safe for the caller to upload
#   2  a listing failed or stale duplicates could not be removed (IDs on stderr)
reconcile_assets() {
  local release_id="$1" name="$2" expected_size="$3" expected_sha="$4"
  local attempt
  for attempt in 1 2 3; do
    local listing kept="" deleted_any="" final_remaining final_kept="" id url
    if ! listing="$(assets_for_release "$release_id" "$name")"; then
      return 2
    fi
    while IFS=$'\t' read -r id url; do
      [[ -n "$id" ]] || continue
      if [[ -z "$kept" && -n "$url" ]] && asset_matches "$url" "$expected_size" "$expected_sha"; then
        kept="$id"
        echo "Gitee asset verified: $name (id=$id)" >&2
        continue
      fi
      deleted_any=1
      echo "Removing duplicate Gitee asset: $name (id=$id)" >&2
      if ! curl --silent --show-error --fail \
        --connect-timeout 15 --max-time 60 \
        --request DELETE \
        --data-urlencode "access_token=$GITEE_TOKEN" \
        "$API/releases/$release_id/attach_files/$id" >/dev/null; then
        echo "DELETE failed for $name (id=$id); will retry" >&2
      fi
    done <<< "$listing"

    # No deletions were attempted: the verified single entry is already the
    # final state, and a second byte-verify of a large DMG would be wasted.
    if [[ -z "$deleted_any" ]]; then
      if [[ -n "$kept" ]]; then
        return 0
      fi
      return 1
    fi

    # Re-list and re-verify: a DELETE response may have been lost even when
    # the deletion succeeded, and the listing may lag behind. Success
    # requires exactly one byte-identical asset and nothing else.
    final_remaining=0
    final_kept=""
    if ! listing="$(assets_for_release "$release_id" "$name")"; then
      return 2
    fi
    while IFS=$'\t' read -r id url; do
      [[ -n "$id" ]] || continue
      final_remaining=$((final_remaining + 1))
      if [[ -z "$final_kept" && -n "$url" ]] && asset_matches "$url" "$expected_size" "$expected_sha"; then
        final_kept="$id"
      fi
    done <<< "$listing"

    if [[ "$final_remaining" == 1 && -n "$final_kept" ]]; then
      return 0
    fi
    if [[ "$final_remaining" == 0 ]]; then
      return 1
    fi
    echo "Duplicate Gitee assets still present for $name ($final_remaining entries); retrying" >&2
    [[ "$attempt" -lt 3 ]] && sleep 2
  done
  echo "Unable to remove duplicate Gitee assets: $name" >&2
  if listing="$(assets_for_release "$release_id" "$name" 2>/dev/null)"; then
    while IFS=$'\t' read -r id url; do
      [[ -n "$id" ]] && echo "  remaining asset id=$id" >&2
    done <<< "$listing"
  fi
  return 2
}

ensure_asset() {
  local tag="$1" file="$2" expected_size="$3" expected_sha="$4"
  local name release_id attempt
  name="$(basename "$file")"
  release_id="$(release_id_for_tag "$tag")" || return 1
  [[ -n "$release_id" ]] || {
    echo "Gitee release $tag does not exist" >&2
    return 1
  }

  for attempt in 1 2 3; do
    if reconcile_assets "$release_id" "$name" "$expected_size" "$expected_sha"; then
      return 0
    else
      # In Bash the `if` statement itself exits 0 when the condition fails,
      # so the command's status is only readable inside the else clause.
      local outcome=$?
    fi
    if [[ "$outcome" == 2 ]]; then
      echo "Unable to reconcile Gitee assets for $name" >&2
      return 1
    fi
    # Nothing matched: upload this file; the next round verifies it (a lost
    # response still leaves the stored bytes discoverable).
    echo "Uploading $name (attempt $attempt/3)" >&2
    if ! curl --silent --show-error --fail \
      --connect-timeout 20 --max-time 300 \
      --request POST \
      --form "access_token=$GITEE_TOKEN" \
      --form "file=@$file" \
      "$API/releases/$release_id/attach_files" >/dev/null; then
      if [[ "$attempt" -lt 3 ]]; then
        sleep $((attempt * 20))
      fi
    fi
  done

  # A successful third upload (or a lost response on the last round) still
  # needs verification: one final read-only reconcile decides.
  if reconcile_assets "$release_id" "$name" "$expected_size" "$expected_sha"; then
    return 0
  fi
  echo "Unable to upload and verify Gitee asset $name after 3 attempts" >&2
  return 1
}

ensure_release() {
  local tag="$1" name="$2" body="${3:-}" prerelease="${4:-false}"
  local release_id
  release_id="$(release_id_for_tag "$tag")" || return 1
  if [[ -n "$release_id" ]]; then
    echo "$release_id"
    return 0
  fi
  echo "Creating Gitee release $tag" >&2
  # The creation response must contain a valid id; a `null`/`{}` body means
  # the creation did not happen and must fail, not echo "null".
  if ! curl --silent --show-error --fail \
    --connect-timeout 15 --max-time 60 \
    --request POST \
    --data-urlencode "access_token=$GITEE_TOKEN" \
    --data-urlencode "tag_name=$tag" \
    --data-urlencode "name=$name" \
    --data-urlencode "body=$body" \
    --data-urlencode "prerelease=$prerelease" \
    "$API/releases" | jq -er '
      select(type == "object")
      | .id
      | select(type == "number" or type == "string")
    ' >/dev/null; then
    echo "Gitee release creation failed for $tag" >&2
    return 1
  fi
  # Confirm the new release is readable before returning its id.
  release_id_for_tag "$tag"
}

list_assets() {
  local tag="$1" release_id
  release_id="$(release_id_for_tag "$tag")" || return 1
  [[ -n "$release_id" ]] || { echo "[]"; return 0; }
  assets_for_release "$release_id" ""
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
