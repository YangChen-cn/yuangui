# YuanGUI release notes

[简体中文](RELEASE_NOTES.zh-CN.md)

## Unreleased — Local Music

- Added Local Music as a third playback source alongside Apple Music and Bilibili, with language-aware source ordering and migration-safe defaults.
- Added explicit file and folder import for MP3, M4A, AAC, WAV, and AIFF; folder traversal runs only inside a user-selected location. FLAC remains disabled pending device-level AVFoundation validation.
- Added security-scoped bookmark persistence, stable `local:<UUID>` track IDs, metadata and embedded-artwork extraction, local playlists and favorites, playback-mode queues, progress restoration, and recoverable missing-file relocation.
- Local lyrics now prefer a matching sidecar `.lrc`, then YuanGUI’s cache, LRCLIB, and manual LRC tools. Desktop lyrics, lyric seeking and offsets, external-audio interruption, and pet listening actions are shared with the existing sources.
- Generalized the AVPlayer engine for both network candidates and local file URLs. Network fallback and the 12-second watchdog remain limited to HTTP/HTTPS playback.

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
