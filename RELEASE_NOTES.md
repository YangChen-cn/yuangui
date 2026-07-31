# YuanGUI release notes

[简体中文](RELEASE_NOTES.zh-CN.md)

## 2.7.2 — Automatic updates, Gitee mirror, and release reliability

- Added a quiet automatic update flow with a real startup delay, daily retry limits, pending prompts, and no background focus stealing. Checks remain silent when the network is unavailable or a modal presentation is active.
- Replaced the unstable update alert with a centered SwiftUI update window that supports Later, View Details, and Update Now while sharing the existing update store and installation pipeline.
- Added Gitee as a domestic metadata and download mirror alongside GitHub. The app compares both valid `updates/latest.json` manifests, prefers the newest compatible version, and falls back from Gitee to GitHub only after a typed download failure.
- Strengthened update validation with HTTPS and strict manifest checks, streamed SHA-256 verification, file-size checks, DMG mounting, Bundle ID/version/build/minimum-system validation, and code-signature verification before installation.
- Restored complete manual update details and localized release-note selection, so manual checks no longer inherit the automatic prompt's two-highlight summary.
- Added release automation that mirrors the same DMG and manifest to Gitee, rejects prereleases from the stable channel, reads version metadata from the DMG itself, serializes manifest publishing, and refuses accidental version downgrades.
- Fixed the Dashboard toolbar update popover closing the entire status panel by deferring the check until presentation is committed and ignoring auxiliary popup windows in the outside-click monitor.
- Made DMG packaging require an explicit stable `VERSION` and positive `BUILD`, preventing stale development defaults from producing an incorrectly versioned installer.

## 2.7.1 — Music performance, SwiftUI lifecycle, and companion polish

- Reduced unnecessary SwiftUI work throughout the music interface. Playback progress, transport controls, lyrics, library, account, Bilibili import, and local import now observe separate stores instead of one broad music wrapper.
- Split the music implementation into focused playback, library, lyrics, Bilibili, local-file, and persistence coordinators while keeping the existing library format, service interfaces, and user-facing behavior compatible.
- Hardened cancellation and shutdown. QR login polling, favorite-folder imports, local imports, file relocation, artwork maintenance, lyric searches, Apple Music refreshes, and URL-player callbacks now reject stale results after cancellation or shutdown.
- Fixed duplicate tracks within a single Bilibili favorite-folder import, late progress updates after cancellation, lyric search remaining stuck in a loading state, and artwork files being left behind when an import or relocation was interrupted.
- Avoided a Bilibili account request when no login session exists, and made Cleanup House scan only enabled categories. This removes the network and filesystem timeout paths that had pushed the GitHub Actions test phase past nine minutes.
- Added deterministic publisher-isolation and suspended-service lifecycle tests. In the recorded 100-update Instruments scenario, `MusicPlayerView` evaluations dropped from 103 to 2 and `MusicProgressView` evaluations from 103 to 1.
- Narrowed SwiftUI refresh boundaries across the Dashboard, desktop companion, Settings, Journal, and music surfaces, while keeping stable panel hosts and detaching hidden Dashboard content from high-frequency updates.
- Added dedicated focus artwork for all three companion modes. Starting Focus now closes its side controls; interaction lock hides the music and lock controls and leaves a read-only countdown badge, and the companion exits the focus action when the timer ends.
- Made mini-player playback and lyric/lock selections visibly stateful with a fixed blue primary treatment. Opening the full player from the mini player now dismisses the popover first and reliably activates the player window.
- Sized lyric bubbles from their actual lyric and alert text, including urgent-reminder appearance, disappearance, pulse, and reminder-mode changes, so badges are not clipped or left in an oversized panel.
- Refined Dashboard Liquid Glass selection into one stable morphing indicator and kept content surfaces restrained with a Material fallback on macOS 15–25.

## 2.7.0 — Local Music, safer cleanup, and a smoother companion

- Added Local Music as a complete third playback source alongside Apple Music and Bilibili. Import MP3, M4A, AAC, WAV, and AIFF files or folders through the system picker, with security-scoped bookmarks, metadata and embedded-artwork extraction, local playlists, favorites, progress restoration, and recoverable missing-file relocation.
- Added library search and stable display-only sorting for Local Music and Bilibili, detailed import failures, Reveal in Finder, and safe orphaned-artwork cleanup after deletion, duplicate imports, and library restoration.
- Local tracks can now import or remove custom cover art. Relocation refreshes title, artist, album, duration, artwork, and matching sidecar LRC while preserving the track ID, favorites, and playlist references.
- Reworked Cleanup House safety and interaction. Scanners and destructive-operation services are now created only after an explicit user action; project roots, category summaries, hard-link-aware sizing, risk-aware quick actions, protected-data rules, scan-time identity checks, shared-data protection, and running-app guidance make review clearer and safer. Project artifacts and old installers go to the Trash only. The full Cleanup House now keeps its scan-scope menus, activity records, and confirmation actions fully localized in English and Simplified Chinese.
- Improved the player and lyrics pipeline across local and network sources. Matching sidecar LRC files take priority over the cache and LRCLIB; lyrics seeking, offsets, desktop lyrics, external-audio interruption, and companion listening actions now share consistent playback state.
- Reworked Focus into a much smaller time-and-controls popover without the oversized dial or duplicated duration. Focus and completion feedback now respect Reduce Motion. AI streaming replies publish at most every 50ms while chat is visible and stay in a non-UI buffer while hidden; the cancellable chat presentation state machine now finishes the card exit before atomically restoring the compact pet window.
- Added time-aware bilingual companion dialogue with per-language and per-character recent-history deduplication.
- Fixed malformed AI-response handling, language-following default prompts, stale chat-dismiss tasks, cross-session streaming leakage, oversized short companion toasts, lyric-bubble truncation, journal creation from empty special views, local artwork lifecycle issues, cleanup-house Chinese leakage in English mode, and an unwanted Desktop Folder permission prompt caused by packaged apps falling back to SwiftPM build resources.
- Added a complete English interface, System/English/Simplified Chinese language selection, localized app metadata and permission guides, plus full GPL-3.0-only, asset-license, and third-party notice documents.

## 2.6.1 — Stability and performance

- Restored persisted desktop lyrics after relaunch and fixed focus-timer duration stability.
- Reduced startup and resident-memory work by creating heavy windows and background tasks on demand.
- Improved desktop-pet edge behavior, lyrics sizing, music playback, and long-running monitoring stability.

## 2.6.0 — Edge storage and Liquid Glass

- Added safer diary persistence and automatic backup/restore workflows.
- Added edge docking, compact monitoring, and macOS 26 Liquid Glass with a Material fallback on macOS 15–25.
