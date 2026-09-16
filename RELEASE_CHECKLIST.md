# 2.9.0 release preparation checklist

Status: the GitHub Release is published (`v2.9.0`, 2026-09-16, DMG
`7f2f06d1f705e7a8b2ce33b67745d76f289e1d99ca0d546258e573194f18bac4`) and the
Gitee release and tag exist. The Gitee DMG and `.sha256` sidecar still have to
be uploaded by hand — the upload stalled on this network — and
`updates/latest.json` is still on 2.8.2 until
`script/mirror_manifest_locally.sh` runs after that upload.

This checklist records the release values and required local verification. The
release scripts remain authoritative for asset, manifest, and mirror
validation.

- Tag: `v2.9.0`
- Title: `YuanGUI 2.9.0`
- Build: `22`
- DMG: `dist/YuanGUI-2.9.0.dmg`
- Bundle ID: `com.yang.yuangui`
- Minimum macOS: `15.0`
- Signing identity: `YuanGui` (registered self-signed identity)
- GitHub Release assets: the exact DMG bytes, `RELEASE_NOTES.md`, and
  `RELEASE_NOTES.zh-CN.md`
- Gitee Release assets: the same DMG bytes and its `.sha256` sidecar
- Manifest sources: GitHub is authoritative; Gitee is the delayed verified
  fallback. Both must publish the identical `updates/latest.json`.

Before publishing, run `swift test --skip 'YuanGUIBenchmarks'` and
`./script/build_and_run.sh --verify`. The default suite never downloads the PDF
conversion runtime, so also exercise it once, which installs into a temporary directory,
converts generated fixtures and removes the runtime again:

```sh
YUANGUI_TEST_PDF_INSTALL=1 swift test --filter PDFConversionTests/testRealInstallationAndPDFConversion
```

Check the packaged app on an Apple Silicon Mac only: PDF conversion is not built for
Intel. Confirm the packaged app and embedded
Finder extension both report `2.9.0 (22)`, carry the `YuanGui` signature, and
pass deep strict verification. Then run the release flow from a clean, pushed
`main`:

```sh
VERSION=2.9.0 BUILD=22 GITEE_TOKEN=... ./script/release.sh
```

The script packages the DMG once, uploads that exact file plus both bilingual
notes to GitHub, verifies and mirrors the same bytes to Gitee, generates the
manifest from the stable GitHub Release timestamp, and checks both raw
manifests before reporting success.

If the Gitee upload stalls (large multipart POSTs hang on a flaky connection),
run it with `--skip-gitee-upload` instead. That still packages the DMG, creates
the GitHub Release and the Gitee release and tag, but leaves the assets to the
publisher and prints the two files to upload plus the command that finishes the
release:

```sh
VERSION=2.9.0 BUILD=22 GITEE_TOKEN=... ./script/release.sh --skip-gitee-upload
VERSION=2.9.0 BUILD=22 GITEE_TOKEN=... ./script/mirror_manifest_locally.sh
```

Do not re-run the packaging step to retry an upload: a second DMG is not
byte-identical to the published one, and the manifest step verifies the local
DMG against the GitHub asset digest.
