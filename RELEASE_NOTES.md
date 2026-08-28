# YuanGUI release notes

[简体中文](RELEASE_NOTES.zh-CN.md)

## 2.8.2 — Stable maintenance release

- New Finder documents now open a native naming prompt with the suggested complete filename selected, so the next action is typing the name, including the extension.
- Recently displayed local and online covers now use a bounded in-memory cache when the menu-bar music panel reopens. This avoids a placeholder flash without retaining the hidden panel's SwiftUI refresh work.
- Cached installed terminals and editors are used while FinderSync starts, then refreshed when apps launch or quit. This removes the repeated application-discovery work that could delay a right-click menu after the extension had been restarted.
- The complete player’s Bilibili and Local Music rows now use their full row width as the double-click play target.
- A matched LRCLIB lyric is now retained for Bilibili tracks. Newly available Bilibili subtitles remain a fallback and no longer replace that selection during playback reloads or login refreshes.
- The menu-bar music panel reuses the mini-player’s interactive cover: click the cover to close the panel and open the complete player.
- Development builds and packaged DMGs now default to the registered `YuanGui` self-signed identity instead of ad-hoc signing. The scripts fail explicitly if that identity is unavailable.

## 2.8.1 — Finder right-click and update reliability improvements

- Reworked the FinderSync menu into a compact native layout: New File, Cut, Paste, Copy, Open in Terminal, and Open in Editor appear without decorative title rows or artificial spacing.
- Added New Blank File with a lightweight native name prompt. The field accepts complete names such as `config.json` or `main.swift`, rejects invalid paths, and preserves the extension when choosing a collision-safe name.
- Expanded Copy into File Name, Full Path, and shell-safe Terminal Argument options, including multi-selection support.
- Open in Terminal now opens the correct selected folder, or the containing folder for a selected file. The main action uses the last available terminal, while a separate chooser lists installed terminals and marks the current default.
- Added the same remembered-default flow for editors. A selected file or folder opens directly in the last available editor, with a separate chooser when more than one supported editor is installed.
- Kaku uses its registered “New Kaku Tab Here” macOS Service to open the selected directory, with an ordinary app launch fallback when the Service is unavailable.
- Fixed the blank-file prompt so it becomes keyboard-active from Finder, and improved cut/paste target resolution and collision handling.
- Development rebuilds and app updates refresh one Finder extension registration while preserving the user's enabled state, avoiding duplicate or short-lived menu entries.
- Fixed sustained-slow-download detection to use a true trailing 10-second window, so a long throttled GitHub transfer can still switch to the matching Gitee asset instead of appearing faster over time.
- Hardened download completion and cancellation. Progress and stall monitors can no longer interrupt the writer during its final flush, and cancelling an update cannot be mistaken for a successful download.
- Update checks and installation now share the same version-and-build decision. An equal version with a higher build is accepted, while switching the pinned update source discards any result started under the previous source and checks again.
- Added real-time download progress in Settings → About: the active source (GitHub or Gitee), percentage, and bytes downloaded, shown as a linear progress bar. After an automatic source switch the bar restarts for the new source instead of continuing a stale percentage.
- Downloading is never slowed by the progress interface: the transfer reports through a side channel, so a busy window cannot make a fast connection look slow and trigger the source switch.
- The update moves to the “preparing to install” phase the moment the download finishes, so checksum, signature, and mount verification no longer show as a stuck 100% download.
- Choosing Update Now in the automatic update prompt opens the About page, keeping the download progress visible while the update installs.
- Reduced redundant high-frequency work in screenshot editing and pet interaction paths: in-progress annotations stay in the canvas until the gesture ends, auxiliary bubble positioning is coalesced, and drag paths reuse the current pet window and screen without changing exported output or interaction behavior.
- Fixed file drag-over behavior so idle actions and ambient/weather announcements remain suppressed while the pet is a drop target, then resume after the interaction ends.
- Strengthened the release pipeline's Gitee asset handling: duplicate names are reconciled to one byte-verified copy, failed verification never deletes an uncertain asset, and every upload is re-read before success is reported.
- Added release preflight checks that require a clean, pushed `main` before external changes and identify the exact dispatched mirror workflow by commit, tag, build, and run ID.

## Earlier releases

- Added local music, safer cleanup workflows, improved lyrics and focus tools, and a more complete bilingual interface. (2.7.0)
- Improved music performance and SwiftUI lifecycle isolation, companion focus actions, mini-player state feedback, lyric-bubble sizing, and Liquid Glass presentation. (2.7.1)
- Added quiet automatic updates, a Gitee availability mirror with GitHub remaining authoritative, stricter update validation, safer packaging, and release automation. (2.7.2)
- Added native translation speech, more reliable music windows, pet-led onboarding and right-click tools, the first FinderSync menu, and selectable update sources with slow-download fallback. (2.8.0)
- Earlier releases also added diary backup and recovery, edge docking, compact monitoring, and the macOS 26 Liquid Glass design with Material fallback. (2.6.0–2.6.1)
