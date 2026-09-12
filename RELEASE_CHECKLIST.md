# 2.9.0 release preparation checklist

This version is in development and has not been published. This checklist records the intended release values and required local
verification. The release scripts remain authoritative for asset, manifest,
and mirror validation.

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
`./script/build_and_run.sh --verify`. Confirm the packaged app and embedded
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
