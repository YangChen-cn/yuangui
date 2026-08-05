# Update release checklist

YuanGUI reads update metadata from the checked-in `updates/latest.json` file.
GitHub is the authoritative source. Gitee serves the same manifest and DMG only
as a delayed availability fallback; the app does not infer a source from the
user's region, language, or IP address.

The GitHub-first DMG download monitors sustained transfer speed: if the
trailing 10-second window (`DownloadSourcePolicy`) averages below 50KB/s, the
app cancels and downloads the same manifest's Gitee asset instead, and
remembers the decision for 30 minutes so the next check prefers Gitee without
re-measuring. The window is a true sliding window — the baseline is the newest
sample at or before `now - window`, never the start of the transfer — so a
long, uniformly slow download stays slow instead of looking faster as history
accumulates. This means the two DMG assets must be byte-identical (the publish
flow already enforces matching size and SHA-256), because a user may switch
sources mid-download.

The update decision compares version first, then build: a same-version
manifest with a higher build counts as an update (repair releases reuse the
semantic version); a candidate without a build number (GitHub API fallback)
never counts on equal versions. The check and install paths share one
comparison (`AppVersionInfo.isNewer`). The Settings → About source picker
(automatic / GitHub / Gitee) pins both the manifest fetch and the download;
switching sources discards the previous check result and re-checks
immediately, so a stale result can never be installed against the wrong
pinned source.

This workflow deliberately does not use a detached manifest signature. The
manifest is fetched over HTTPS, its schema and URLs are validated, and every
listed asset is checked by SHA-256 and size before it is mounted. The downloaded
DMG is then mounted read-only and checked for `YuanGUI.app`, bundle ID,
version/build, minimum macOS version, code signature, and a writable install
location. The existing data-save and safe-termination flow remains the final
gate before replacement.

## Generate a manifest

Build the DMG locally, then run:

```sh
UPDATE_VERSION=2.7.2 \
UPDATE_BUILD=18 \
DMG_PATH="$PWD/dist/YuanGUI-2.7.2.dmg" \
GITHUB_DMG_URL="https://github.com/YangChen-cn/yuangui/releases/download/v2.7.2/YuanGUI-2.7.2.dmg" \
UPDATE_RELEASE_PAGE_URL="https://github.com/YangChen-cn/yuangui/releases/tag/v2.7.2" \
UPDATE_HIGHLIGHTS_ZH_JSON='["更新亮点一","更新亮点二"]' \
UPDATE_HIGHLIGHTS_EN_JSON='["What is new","Another improvement"]' \
./script/generate_update_manifest.sh
```

`GITEE_DMG_URL` is optional. Leave it unset unless the exact same DMG has been
uploaded to a verified Gitee download URL. The script never invents a Gitee
asset, never uploads files, and prints the local file size and SHA-256.

To validate an existing manifest against a local DMG:

```sh
UPDATE_MANIFEST_PATH="$PWD/updates/latest.json" \
DMG_PATH="$PWD/dist/YuanGUI-2.7.2.dmg" \
./script/verify_update_manifest.sh
```

## Publish and mirror

The repository contains `.github/workflows/mirror-release-to-gitee.yml`. It is
the manifest-and-mirror path for the verified Gitee repository
`yangchen716/yuangui`; the DMG upload itself runs on the publisher's machine
(see below).

### Full flow

1. Switch version sources to the target version manually (semantic edits the
   machine must not guess): `AppVersionInfo` fallback, `script/build_and_run.sh`,
   both Release Notes files, README version references, and the app-localized
   About highlights. Run `swift test` and `./script/build_and_run.sh --verify`,
   then commit and push.
2. Prepare both complete release-note files for the new version:
   `RELEASE_NOTES.md` in English and `RELEASE_NOTES.zh-CN.md` in Simplified
   Chinese. Every release must publish both files; neither language may be
   replaced by the GitHub Release body or by the two-line manifest summary.
3. Publish a stable GitHub Release with exactly one `YuanGUI-*.dmg` plus both
   release-note files as assets, and a `Build: N` line in the body. Prerelease
   tags and prerelease Releases are rejected from `latest.json`.
4. Upload the DMG to Gitee from your machine:
   `VERSION=2.8.1 BUILD=20 GITEE_TOKEN=xxx ./script/publish_gitee_release.sh`
   (creates or reuses the Gitee release, uploads DMG + `.sha256` sidecar with
   reuse-and-verify rules, prints the release URL). Asset handling is
   delegated to `script/gitee_release_assets.sh`.
5. Generate and mirror the manifest from your machine:
   `VERSION=2.8.1 BUILD=20 GITEE_TOKEN=xxx ./script/mirror_manifest_locally.sh`
   It verifies the local DMG against the GitHub Release asset digest, keeps
   the Gitee DMG byte-identical (reusing the upload from step 4), extracts
   the bilingual highlights from the two release-note files, refuses a true
   downgrade unless `ALLOW_ROLLBACK=true`, generates and validates
   `updates/latest.json`, commits it to GitHub main, writes it to Gitee
   through the contents API, and polls the Gitee raw manifest until its bytes
   match.
6. Check both raw URLs and compare their response body (see "Verify" below).

### One-command alternative

After the manual version-switch commit, `script/release.sh` performs steps
2–6:

```sh
VERSION=2.8.1 BUILD=20 GITEE_TOKEN=xxx ./script/release.sh
```

It packages the DMG, creates or completes the GitHub Release with the three
assets, runs the local Gitee upload, generates and mirrors the manifest
locally, and verifies both raw manifests. It never edits sources or
repository configuration. Step 0 — before any external side effect — fetches
`origin/main` and stops unless the local HEAD is pushed and the working tree
is clean, so a release is never built from uncommitted code and never left
half-published.

Configure the repository secret `GITEE_TOKEN` with permission to create a
Gitee release and update the mirrored repository.

### Why everything Gitee-related runs locally

GitHub Actions cloud runners can hang indefinitely on Gitee's large multipart
uploads, and the same flakiness affects the verification download of a large
Gitee asset from the cloud runner (the mirror job got stuck on it repeatedly).
The DMG upload, the byte verification, and the manifest mirror therefore all
run from the publisher's machine, where Gitee is fast and reliable. The
`ensure-asset` call reuses the verified asset; each round is bounded to 300
seconds so failures surface fast.
Both callers invoke the same `script/gitee_release_assets.sh`, which keeps
exactly one byte-identical asset per name and deletes every other same-name
entry (Gitee allows duplicate asset names, and the release-detail API omits
asset ids — reads and deletes go through `attach_files`), then uploads only
when no asset matches. Success requires a re-listed, re-verified exactly-one
state; a successful third upload still gets a final read-only verification,
and deletion failures are retried and then fatal with the undeleted ids
reported. Asset verification is three-way — bytes match, confirmed mismatch,
or verification-download failed — and only confirmed mismatches (and
verified duplicates) are ever deleted: an asset that cannot be verified is
kept, and if verification keeps failing the operation fails instead of
destroying a possibly-correct asset. Release lookup reads the HTTP status explicitly: Gitee reports a
missing tag as HTTP 200 with a literal `null` body (the only "may create"
case); every other status, a network failure, or a 200 body without a valid
id aborts instead of being guessed as missing, and a created release is
re-read before its id is returned. The script's stdout carries only
machine-readable results; logs go to stderr, so
`RELEASE_ID="$(... ensure-release ...)"` stays a pure id. (Bash note: a
failed `if` condition makes the whole statement exit 0, so a command's exit
status must be read inside the `else` clause, never after `fi`.)

For a CLI release, the required asset upload is equivalent to:

```sh
gh release upload "v$VERSION" \
  "dist/YuanGUI-$VERSION.dmg" \
  RELEASE_NOTES.md \
  RELEASE_NOTES.zh-CN.md
```

The mirror script deliberately fails when either release-note asset is absent
on the GitHub Release. It derives each language's manifest highlights from
the matching repository file, so a missing Chinese file cannot silently
publish English text under `zh-Hans`.

The GitHub Actions workflow now has no release job at all: the DMG upload and
the manifest mirror run on the publisher's machine, and a release-triggered
run would race them. The push event only runs the `sync-manifest` job, which
keeps a later manual edit of `updates/latest.json` on GitHub main in sync
with Gitee through the contents API — a small JSON write that is reliable
even from a cloud runner. The mirror script verifies the local DMG bytes
against the GitHub Release asset digest (no download), reconciles the DMG and
its `.sha256` sidecar with Gitee through the shared asset script, downloads
the Gitee DMG again from the publisher's machine, and requires the size and
SHA-256 to match before generating `updates/latest.json`. It does not mount
or inspect the DMG bundle; the app's existing installation checks remain
responsible for Bundle ID, version/build, minimum macOS version, and
code-signature validation. A candidate lower than the current stable manifest
is refused unless `ALLOW_ROLLBACK=true`; an equal version is allowed so
interrupted uploads and manifest repairs can be retried idempotently. For an
uncertain Gitee upload response, the shared asset script re-reads the release
and verifies any same-named asset before retrying, for up to three upload
rounds.
The production manifest URL is therefore:

```text
https://gitee.com/yangchen716/yuangui/raw/main/updates/latest.json
```

The workflow does not create a detached signature and does not put a private
key or token in the repository.

1. Upload the one verified DMG and both localized Release Notes to the GitHub
   Release.
2. If a Gitee DMG asset is available, upload the same bytes and regenerate the
   manifest with `GITEE_DMG_URL` set.
3. Commit and publish `updates/latest.json` to the GitHub `main` branch.
4. Wait for the read-only Gitee repository mirror to contain that commit.
5. Check both raw URLs and compare their response body:

```sh
curl -fL https://raw.githubusercontent.com/YangChen-cn/yuangui/main/updates/latest.json
curl -fL https://gitee.com/yangchen716/yuangui/raw/main/updates/latest.json
```

The Gitee repository is not modified by the app or by the local packaging
scripts. If its raw manifest is not available yet, the app falls back to the
other source or the existing GitHub Releases API and keeps automatic failures
silent.

Manual and automatic checks use the same authority rule: GitHub starts first,
Gitee starts later as a hedge, and a valid GitHub manifest always wins within
the primary-source deadline. Gitee can only be adopted for typed network
availability failures or a missed primary deadline; malformed or unsafe GitHub
metadata must fail instead of switching sources. When the selected version
matches a GitHub Release, the manual About page loads the complete localized
release-note asset instead of limiting the view to the two manifest highlights.

## Security boundary

SHA-256 detects a damaged download or bytes that do not match the manifest. It
does not independently authenticate the manifest because this release does not
implement digital signing. Trust therefore depends on HTTPS, repository account
security, and the existing app bundle, code-signature, version, and safe-exit
checks.
