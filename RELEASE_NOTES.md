# YuanGUI release notes

[简体中文](RELEASE_NOTES.zh-CN.md)

## 2.8.0 — Native translation speech and more reliable music windows

- Redesigned the selection translation window with a lighter, more compact macOS interface that matches the rest of YuanGUI. Source text, translated text, status, language selection, and replacement actions now have clearer visual hierarchy and more reliable dynamic sizing.
- Added native macOS speech synthesis for both source and translated text, with independent controls and automatic language-aware voice selection. Only one side speaks at a time, and stale speech stops immediately when the text, target language, translation result, or window lifecycle changes.
- Improved translation and companion feedback while preventing translation activity from displacing urgent battery or memory reminders.
- Improved the Dashboard Apple Music presentation and strengthened playback synchronization. Polling now recovers after unexpected interruption, track changes no longer remain stuck at the previous song's end, and returning the companion from edge docking triggers an immediate refresh.
- Made LRCLIB matching more tolerant of missing duration metadata. When title-and-artist matching fails, YuanGUI now retries by title so lyrics entries without artist metadata can still be found.
- Added Chinese lyric display conversion with automatic system-language selection, explicit Simplified or Traditional modes, and an unchanged mode. Conversion is presentation-only and does not alter raw LRC data, search, or timeline matching.
- Restored the compact SwiftUI mini-player popover presentation and rebuilt the full-player handoff around the real AppKit popover lifecycle. YuanGUI now closes the parent-owned popover first, waits for it to finish, activates the application, and only then makes the full player key and main.
- The mini player now opens the full player when its artwork is clicked and uses the entire circular play/pause control as the hit target.
- Added focused lifecycle and synchronization tests for speech invalidation, translation window sizing, urgent reminder priority, Apple Music recovery, LRCLIB fallback, and mini-player window handoff.

## Earlier releases

- Added local music, safer cleanup workflows, improved lyrics and focus tools, and a more complete bilingual interface. (2.7.0)
- Improved music performance and SwiftUI lifecycle isolation, companion focus actions, mini-player state feedback, lyric-bubble sizing, and Liquid Glass presentation. (2.7.1)
- Added quiet automatic updates, a Gitee availability mirror with GitHub remaining authoritative, stricter update validation, safer packaging, and release automation. (2.7.2)
- Earlier releases also added diary backup and recovery, edge docking, compact monitoring, and the macOS 26 Liquid Glass design with Material fallback. (2.6.0–2.6.1)
