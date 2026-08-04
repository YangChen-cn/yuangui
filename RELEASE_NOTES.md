# YuanGUI release notes

[简体中文](RELEASE_NOTES.zh-CN.md)

## 2.8.0 — Native translation speech and more reliable music windows

- Redesigned the selection translation window with a lighter, more compact macOS interface that matches the rest of YuanGUI. Source text, translated text, status, language selection, and replacement actions now have clearer visual hierarchy and more reliable dynamic sizing.
- Added native macOS speech synthesis for both source and translated text, with independent controls and automatic language-aware voice selection. Only one side speaks at a time, and stale speech stops immediately when the text, target language, translation result, or window lifecycle changes.
- Improved translation and companion feedback while preventing translation activity from displacing urgent battery or memory reminders.
- Improved the Dashboard Apple Music presentation and strengthened playback synchronization. Polling now recovers after unexpected interruption, track changes no longer remain stuck at the previous song's end, and returning the companion from edge docking triggers an immediate refresh.
- Made LRCLIB matching more tolerant of missing duration metadata. When title-and-artist matching fails, YuanGUI now retries by title so lyrics entries without artist metadata can still be found.
- Added Chinese lyric display conversion with automatic system-language selection, explicit Simplified or Traditional modes, and an unchanged mode. Conversion is presentation-only and does not alter raw LRC data, search, or timeline matching.
- Restored the compact SwiftUI mini-player popover presentation and rebuilt the full-player handoff around the real AppKit popover lifecycle. 
- The mini player now opens the full player when its artwork is clicked and uses the entire circular play/pause control as the hit target.
- Fixed lifecycle race condition when opening the mini player for the first time
- Added focused lifecycle and synchronization tests for speech invalidation, translation window sizing, urgent reminder priority, Apple Music recovery, LRCLIB fallback, and mini-player window handoff.
- Added a native FinderSync extension for creating common text and Office files, copying paths, opening the selected folder in installed terminal apps such as Kaku, and cutting or pasting items from Finder context menus.
- Finder extension actions now survive Finder's XPC menu bridge reliably, use collision-safe file names, and refresh in place during development builds or app updates without toggling the user's extension setting or registering duplicate copies.
- The companion now walks new users through the app itself: a first-launch guide bubble introduces the pet, teaches the right-click tools menu (with a temporary unlock option for locked pets), tries real screenshots and screenshot translation, and explains the Finder extension. Every step can be skipped, and completion is recorded so it never auto-starts again.
- The pet's right-click menu becomes the entry point to the tools: region screenshot, screenshot translation, selection translation, focus, music, diary, Finder extension management, re-watching the guide, and Settings. The menu is bound to the character sprite only, so the chat composer and transparent margins keep their native behaviors.
- Added one-time feature tips (selection translation, screenshot translation, focus, diary, music, Finder extension) that only appear while the pet is idle, skip features you have already used, wait at least 30 minutes between attempts, and can be turned off in Settings → General. Existing users are never treated as fresh installs.
- Guide bubbles follow the same priority rules as the rest of the pet's messages: urgent reminders and running tasks outrank the guide, and the guide outranks lyrics, weather and casual chatter. The bubble sizes itself to its content instead of clipping long text.
- The walkthrough's temporary unlock is a runtime-only state: the persisted interaction-lock preference is never changed and is restored on every exit path.
- A screenshot step can no longer stall the walkthrough: capture sessions report their start synchronously (true/false), and each started session reports exactly one end whether the capture succeeded, was cancelled, or failed.
- GitHub-first downloads now monitor sustained transfer speed: if the average stays below 50KB/s over a 10-second window, the app switches to the same manifest's Gitee asset and remembers the decision for 30 minutes, so a reachable-but-throttled connection no longer stalls the update.
- Settings → About lets you pin the update source: Automatic (the default) keeps GitHub authoritative with the slow-download switch, or you can force GitHub or Gitee for both the update check and the download.

## Earlier releases

- Added local music, safer cleanup workflows, improved lyrics and focus tools, and a more complete bilingual interface. (2.7.0)
- Improved music performance and SwiftUI lifecycle isolation, companion focus actions, mini-player state feedback, lyric-bubble sizing, and Liquid Glass presentation. (2.7.1)
- Added quiet automatic updates, a Gitee availability mirror with GitHub remaining authoritative, stricter update validation, safer packaging, and release automation. (2.7.2)
- Earlier releases also added diary backup and recovery, edge docking, compact monitoring, and the macOS 26 Liquid Glass design with Material fallback. (2.6.0–2.6.1)
