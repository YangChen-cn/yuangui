# 2.8.2 stable release checklist

This checklist records the exact stable-release values and required local
verification. The release scripts remain authoritative for asset, manifest,
and mirror validation.

- Tag: `v2.8.2`
- Title: `YuanGUI 2.8.2`
- Build: `21`
- DMG: `dist/YuanGUI-2.8.2.dmg`
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
Finder extension both report `2.8.2 (21)`, carry the `YuanGui` signature, and
pass deep strict verification. Then run the release flow from a clean, pushed
`main`:

```sh
VERSION=2.8.2 BUILD=21 GITEE_TOKEN=... ./script/release.sh
```

The script packages the DMG once, uploads that exact file plus both bilingual
notes to GitHub, verifies and mirrors the same bytes to Gitee, generates the
manifest from the stable GitHub Release timestamp, and checks both raw
manifests before reporting success.
