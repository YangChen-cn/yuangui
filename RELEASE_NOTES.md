# YuanGUI release notes

[简体中文](RELEASE_NOTES.zh-CN.md)

## 2.7.0 — English localization and global-release preparation

- Added English and Simplified Chinese resource bundles, a System/English/Simplified Chinese preference, localized app metadata, and restart guidance.
- New English installations use an English companion prompt, English place-name lookup, and non-English-to-English translation defaults. Existing prompts and translation settings are retained.
- Cleanup House now reviews reproducible developer caches, project build artifacts, and old installer packages. The latter two are moved to the Trash only.
- Added conservative project-root management, category summaries, hard-link-aware size accounting, stronger scan-time identity checks, expanded protected software/data rules, and “quit then rescan” behavior for running apps.
- Added English/Chinese installation and permission guides, GPL-3.0-only and asset licensing materials, third-party notices, and DMG legal documents.

## 2.6.1 — Stability and performance

- Restored persisted desktop lyrics after relaunch and fixed focus-timer duration stability.
- Reduced startup and resident-memory work by creating heavy windows and background tasks on demand.
- Improved desktop-pet edge behavior, lyrics sizing, music playback, and long-running monitoring stability.

## 2.6.0 — Edge storage and Liquid Glass

- Added safer diary persistence and automatic backup/restore workflows.
- Added edge docking, compact monitoring, and macOS 26 Liquid Glass with a Material fallback on macOS 15–25.
