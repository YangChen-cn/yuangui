# Update release checklist

YuanGUI reads update metadata from the checked-in `updates/latest.json` file.
The same manifest can be served by the Gitee mirror and by the GitHub raw URL;
the app does not infer a preferred source from the user's region or language.

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
UPDATE_VERSION=2.7.1 \
UPDATE_BUILD=17 \
DMG_PATH="$PWD/dist/YuanGUI-2.7.1.dmg" \
GITHUB_DMG_URL="https://github.com/YangChen-cn/yuangui/releases/download/v2.7.1/YuanGUI-2.7.1.dmg" \
UPDATE_RELEASE_PAGE_URL="https://github.com/YangChen-cn/yuangui/releases/tag/v2.7.1" \
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
DMG_PATH="$PWD/dist/YuanGUI-2.7.1.dmg" \
./script/verify_update_manifest.sh
```

## Publish and mirror

1. Upload the one verified DMG to the GitHub Release.
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

## Security boundary

SHA-256 detects a damaged download or bytes that do not match the manifest. It
does not independently authenticate the manifest because this release does not
implement digital signing. Trust therefore depends on HTTPS, repository account
security, and the existing app bundle, code-signature, version, and safe-exit
checks.
