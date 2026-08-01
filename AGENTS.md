# YuanGUI agent guide

This file contains the constraints an automated coding agent must keep in mind
throughout work on this repository. Current code and tests are authoritative;
inspect them before relying on historical notes.

## Start every task safely

- Read the user's latest request, then run `git status --short --branch` and
  inspect the relevant files before editing.
- Preserve all existing user changes. Never clean the worktree with
  `git reset --hard`, `git checkout --`, or another destructive shortcut.
- Use `rg`/`rg --files` for discovery and `apply_patch` for hand-written edits.
- `.codex/` is local and ignored. Never stage or commit
  `.codex/AI_CONTEXT.md` unless the user explicitly overrides this rule.
- Do not commit, push, tag, create a Release, replace assets, or publish unless
  the user explicitly asks. Commit messages must be in English.

## Product and platform baseline

- YuanGUI is a SwiftPM macOS SwiftUI/AppKit application, not a command-line
  product. Bundle ID: `com.yang.yuangui`; minimum deployment target: macOS 15.
- Current stable version is 2.7.2, build 18. Packaged builds read version data
  from `Info.plist`; source fallbacks live in `AppVersionInfo`.
- The app starts as an accessory app and uses custom AppKit windows and panels.
  Preserve menu-bar anchoring, Spaces behavior, outside-click handling, dynamic
  sizing, keyboard shortcuts, and safe window activation.
- macOS 26 uses native Liquid Glass APIs behind availability checks. macOS
  15–25 must retain restrained Material fallbacks. Glass belongs on transient
  controls, toolbars, pickers, speech bubbles, and floating controls—not diary
  bodies, long lists, forms, lyrics content, or every card.
- Preserve Reduce Motion, Reduce Transparency, increased contrast, low-power
  behavior, keyboard navigation, and accessibility labels.

## Architecture boundaries

- Normal flow is `SwiftUI View -> focused Observable store -> service`.
  AppKit owns window mechanics; SwiftUI owns presentation content.
- Form real refresh boundaries with independent `View` types. Root views should
  hold ordinary references where possible; put `@ObservedObject` only in the
  smallest view that reads that object's published state. Do not pass a whole
  store to unrelated leaves or observe the same store in both parent and child.
- `MusicFeature` is a non-Observable facade. Never restore an aggregate music
  `ObservableObject`, service locator, runtime wrapper, or broad
  `objectWillChange`. Playback, progress, library, lyrics, presentation,
  Bilibili, and local import remain independently observed domains.
- Async coordinators own cancellable task handles/generations. After every
  uncontrollable `await`, reject stale, cancelled, or shutdown results before
  mutating UI or persistence.
- Do not duplicate business state between SwiftUI and AppKit. Route app actions
  through `AppActions`/`WindowCoordinator`; system notifications may remain.
- Never hard-code a user's home, Desktop, build, or resource path. Use system
  APIs, security-scoped URLs, app bundles, or SwiftPM resource bundles.

## Data and feature safety

- Diary edits must retain revision-safe autosave, `flush()` on close/update/
  termination, corrupt-entry isolation, attachment limits, backup validation,
  and rollback-safe restore. Tests must use injected temporary storage, never
  production Application Support.
- Cleanup scans and destructive services are created only after explicit user
  action. Preserve risk filtering, identity revalidation, protected/shared-data
  rules, and Trash-based handling for recoverable items.
- Screenshot/OCR/file-picker flows must not be interrupted by unrelated prompts
  or activation. Do not introduce startup scans of Desktop, Documents,
  Downloads, Music, or the home directory.
- Chat streaming must remain session-ID and generation safe. Hidden chat may
  buffer text but must not drive high-frequency SwiftUI publishing.
- Pet auxiliary bubbles stay in their independent panel; do not resize the main
  pet panel to show lyrics, status, maintenance, or timer content.

## Update-system invariants

- GitHub is the authoritative metadata and DMG source. Gitee is only a delayed
  network-availability fallback; a newer Gitee version never overrides a valid
  GitHub manifest.
- Manifest fetching is hedged: GitHub starts immediately, Gitee starts after
  about two seconds, GitHub has an approximately five-second primary deadline,
  and the backup has a bounded overall deadline.
- Only typed availability failures permit source fallback: timeout, DNS/host/
  connection loss, offline/resource unavailable, HTTP 408/429, and HTTP 5xx.
  Parsing, schema, version, minimum-system, URL, SHA, size, mount, bundle,
  version/build, signature, or local installation failures must stop.
- Downloads prefer GitHub unless the current check or the 30-minute cache has
  already established GitHub unavailability. Never catch every `Error` and
  switch mirrors indiscriminately.
- Keep HTTPS, positive size, streamed SHA-256, read-only DMG mounting,
  `YuanGUI.app`, Bundle ID, version/build, minimum macOS, existing ad-hoc
  `codesign --verify --deep --strict`, writable target, diary flush, and safe
  termination checks.
- This project intentionally does not implement a signed manifest, Developer
  ID signing, or notarization. Do not add keys or claim SHA-256 authenticates
  the manifest; trust also depends on HTTPS and repository account security.
- Automatic failures stay quiet and do not steal focus. Pending prompts show
  only after explicit safe interaction with YuanGUI and after transient panels
  are hidden. Manual checks retain complete localized Release Notes; the
  automatic prompt shows at most two highlights.

## Validation

- Default product tests:

  ```sh
  swift test --skip 'YuanGUIBenchmarks'
  ```

- Benchmarks are separate and must not be folded into ordinary unit tests:

  ```sh
  ./script/benchmark_translation.sh
  ./script/benchmark_diary.sh
  ```

- For normal code changes, after tests pass build and launch the packaged app:

  ```sh
  ./script/build_and_run.sh --verify
  ```

- Do not report GUI behavior as verified unless it was actually observed.
  Clearly list multi-display, permissions, Spaces, drag/drop, picker, and other
  environment-dependent checks that still require manual validation.
- Keep tests behavior-focused. Merge repetitive parameter cases into table-
  driven scenarios, but never remove security, lifecycle, cancellation,
  persistence, fallback, or user-visible behavior coverage merely to reduce a
  test count.

## Release rules

- `script/package_dmg.sh` requires explicit stable `VERSION` and positive
  `BUILD`; never restore stale defaults. Build the DMG once and upload the exact
  same bytes to GitHub and Gitee.
- Every stable GitHub Release must contain all three assets:
  `YuanGUI-<version>.dmg`, `RELEASE_NOTES.md`, and
  `RELEASE_NOTES.zh-CN.md`. Both notes files must contain the complete matching
  version section; neither is optional.
- Keep app-localized About highlights, both Release Notes files, README version
  references, package metadata, and release metadata synchronized.
- `.github/workflows/mirror-release-to-gitee.yml` runs release mirroring on
  Ubuntu, verifies Gitee DMG size/SHA, uploads the `.sha256` sidecar, generates
  `updates/latest.json`, and verifies Gitee raw content. It rejects prereleases
  and true downgrades; same-version repair runs are intentionally allowed.
- Manifest `publishedAt` must use the stable GitHub Release `published_at`, not
  workflow execution time, so same-version reruns stay idempotent.
- Gitee `remote_mirror/pull` currently returns 404. The workflow therefore uses
  the Contents API and polls raw cache when needed. A new Gitee upload can take
  several minutes even after bytes reach the server; preserve the safe timing
  diagnostics and verify uncertain uploads before retrying.
- Follow the complete checklist in `docs/UPDATE_RELEASE.md`. Never invent asset
  URLs, hashes, builds, Gitee attachments, signatures, or successful uploads.
