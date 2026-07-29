# YuanGUI release notes

[简体中文](RELEASE_NOTES.zh-CN.md)

## 2.7.0 — Local Music, safer cleanup, and a smoother companion

- Added Local Music as a complete third playback source alongside Apple Music and Bilibili. Import MP3, M4A, AAC, WAV, and AIFF files or folders through the system picker, with security-scoped bookmarks, metadata and embedded-artwork extraction, local playlists, favorites, progress restoration, and recoverable missing-file relocation.
- Added library search and stable display-only sorting for Local Music and Bilibili, detailed import failures, Reveal in Finder, and safe orphaned-artwork cleanup after deletion, duplicate imports, and library restoration.
- Local tracks can now import or remove custom cover art. Relocation refreshes title, artist, album, duration, artwork, and matching sidecar LRC while preserving the track ID, favorites, and playlist references.
- Reworked Cleanup House safety and interaction. Scanners and destructive-operation services are now created only after an explicit user action; project roots, category summaries, hard-link-aware sizing, risk-aware quick actions, protected-data rules, scan-time identity checks, shared-data protection, and running-app guidance make review clearer and safer. Project artifacts and old installers go to the Trash only. The full Cleanup House now keeps its scan-scope menus, activity records, and confirmation actions fully localized in English and Simplified Chinese.
- Improved the player and lyrics pipeline across local and network sources. Matching sidecar LRC files take priority over the cache and LRCLIB; lyrics seeking, offsets, desktop lyrics, external-audio interruption, and companion listening actions now share consistent playback state.
- Reworked Focus into a much smaller time-and-controls popover without the oversized dial. AI streaming replies are throttled to 50ms UI updates, and chat, pet, and control layers now transition independently to avoid redundant window redraws.
- Added time-aware bilingual companion dialogue with per-language and per-character recent-history deduplication.
- Fixed malformed AI-response handling, language-following default prompts, lyric-bubble truncation, journal creation from empty special views, local artwork lifecycle issues, cleanup-house Chinese leakage in English mode, and an unwanted Desktop Folder permission prompt caused by packaged apps falling back to SwiftPM build resources.
- Added a complete English interface, System/English/Simplified Chinese language selection, localized app metadata and permission guides, plus full GPL-3.0-only, asset-license, and third-party notice documents.

## 2.6.1 — Stability and performance

- Restored persisted desktop lyrics after relaunch and fixed focus-timer duration stability.
- Reduced startup and resident-memory work by creating heavy windows and background tasks on demand.
- Improved desktop-pet edge behavior, lyrics sizing, music playback, and long-running monitoring stability.

## 2.6.0 — Edge storage and Liquid Glass

- Added safer diary persistence and automatic backup/restore workflows.
- Added edge docking, compact monitoring, and macOS 26 Liquid Glass with a Material fallback on macOS 15–25.
