# YuanGUI release notes

[简体中文](RELEASE_NOTES.zh-CN.md)

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
- Strengthened the release pipeline's Gitee asset handling: duplicate names are reconciled to one byte-verified copy, failed verification never deletes an uncertain asset, and every upload is re-read before success is reported.
- Added release preflight checks that require a clean, pushed `main` before external changes and identify the exact dispatched mirror workflow by commit, tag, build, and run ID.

## Earlier releases

- Added local music, safer cleanup workflows, improved lyrics and focus tools, and a more complete bilingual interface. (2.7.0)
- Improved music performance and SwiftUI lifecycle isolation, companion focus actions, mini-player state feedback, lyric-bubble sizing, and Liquid Glass presentation. (2.7.1)
- Added quiet automatic updates, a Gitee availability mirror with GitHub remaining authoritative, stricter update validation, safer packaging, and release automation. (2.7.2)
- Added native translation speech, more reliable music windows, pet-led onboarding and right-click tools, the first FinderSync menu, and selectable update sources with slow-download fallback. (2.8.0)
- Earlier releases also added diary backup and recovery, edge docking, compact monitoring, and the macOS 26 Liquid Glass design with Material fallback. (2.6.0–2.6.1)
