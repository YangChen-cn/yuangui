# Update release checklist

YuanGUI reads update metadata from the checked-in `updates/latest.json` file.
GitHub is the authoritative source. Gitee serves the same manifest and DMG only
as a delayed availability fallback; the app does not infer a source from the
user's region, language, or IP address.

The GitHub-first DMG download monitors sustained transfer speed: if the average
stays below 50KB/s over a 10-second window (`DownloadSourcePolicy`), the app
cancels and downloads the same manifest's Gitee asset instead, and remembers
the decision for 30 minutes so the next check prefers Gitee without
re-measuring. This means the two DMG assets must be byte-identical (the
publish flow already enforces matching size and SHA-256), because a user may
switch sources mid-download.

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
   `VERSION=2.8.0 BUILD=19 GITEE_TOKEN=xxx ./script/publish_gitee_release.sh`
   (creates or reuses the Gitee release, uploads DMG + `.sha256` sidecar with
   reuse-and-verify rules, prints the release URL).
5. Dispatch the mirror workflow:
   `gh workflow run mirror-release-to-gitee.yml -f tag=v2.8.0 -f build=19
   -f minimum_system_version=15.0`. It verifies the Gitee bytes against the
   GitHub Release, generates `updates/latest.json`, commits it to main, and
   mirrors it to Gitee.
6. Wait for the read-only Gitee repository mirror, then check both raw URLs
   and compare their response body (see "Verify" below).

### One-command alternative

After the manual version-switch commit, `script/release.sh` performs steps
2–6:

```sh
VERSION=2.8.0 BUILD=19 GITEE_TOKEN=xxx ./script/release.sh
```

It packages the DMG, creates or completes the GitHub Release with the three
assets, runs the local Gitee upload, dispatches and waits for the mirror
workflow, and verifies both raw manifests. It never edits sources or
repository configuration.

Configure the repository secret `GITEE_TOKEN` with permission to create a
Gitee release and update the mirrored repository.

### Why uploads run locally

GitHub Actions cloud runners can hang indefinitely on Gitee's large multipart
uploads, while the same upload from a normal network takes seconds. The DMG is
therefore uploaded locally, and the workflow reuses the verified asset. The
workflow's own upload step remains only as a fallback when the asset is
missing; each round is bounded to 300 seconds so failures surface fast.

For a CLI release, the required asset upload is equivalent to:

```sh
gh release upload "v$VERSION" \
  "dist/YuanGUI-$VERSION.dmg" \
  RELEASE_NOTES.md \
  RELEASE_NOTES.zh-CN.md
```

The workflow deliberately fails when either release-note asset is absent. It
downloads the two files and derives each language's manifest highlights from
the matching document, so a missing Chinese file cannot silently publish
English text under `zh-Hans`.

The release job runs on `ubuntu-latest`. It downloads the exact GitHub DMG and
both mandatory localized release-note assets,
computes its SHA-256 and size with Linux tools, uploads that same file and its
`.sha256` sidecar to Gitee, downloads the Gitee DMG again, and requires the
size and SHA-256 to match before generating `updates/latest.json`. It does not
mount or inspect the DMG bundle in CI; the app's existing installation checks
remain responsible for Bundle ID, version/build, minimum macOS version, and
code-signature validation. A release event reads `Build: N` from the GitHub
Release body. A manual dispatch must provide `build` and may provide
`minimum_system_version`; an interrupted same-version repair can reuse those
values from the current manifest. The workflow then commits the manifest to
GitHub `main` and requests a Gitee mirror refresh. If a same-named Gitee asset
already exists, the workflow reuses it only after downloading and matching its
size and SHA-256; stale content is deleted and uploaded again. If the
repository mirror is not configured, it uses the Gitee contents API to create
or update that one manifest file. It then compares the Gitee raw response with
the GitHub file.
All release and manual runs share one non-canceling concurrency group. A
candidate lower than the current stable manifest is refused unless
`allow_rollback` is explicitly enabled for a manual run; an equal version is
allowed so interrupted uploads and manifest repairs can be retried idempotently.
For an uncertain Gitee upload response, the workflow re-reads the release and
verifies any same-named asset before retrying, for up to three upload rounds.
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
