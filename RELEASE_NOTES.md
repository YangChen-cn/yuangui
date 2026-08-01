# YuanGUI release notes

[简体中文](RELEASE_NOTES.zh-CN.md)

## 2.7.2 — Automatic updates, Gitee mirror, and release reliability

- Added a quiet automatic update flow with a real startup delay, daily retry limits, pending prompts, and no background focus stealing. Checks remain silent when the network is unavailable or a modal presentation is active.
- Replaced the unstable update alert with a centered SwiftUI update window that supports Later, View Details, and Update Now while sharing the existing update store and installation pipeline.
- Added Gitee as a domestic metadata and download mirror with GitHub remaining the authoritative source. GitHub is requested first; Gitee starts only as a delayed hedge when the primary source is still unavailable, and a valid GitHub manifest always wins. Only typed network-availability failures permit the fallback; malformed or unsafe manifests never silently switch sources.
- Aligned downloads with the same source policy: a verified GitHub DMG is used first, while Gitee is tried only when GitHub cannot establish or maintain a network connection. Checksum, size, bundle, version, mount, or code-signature failures stop immediately instead of masking an integrity problem as a mirror outage.
- Fixed the delayed-fallback deadline so an already-started Gitee request can finish after GitHub's primary deadline, and the selected Gitee metadata can be reused for installation without waiting on GitHub a second time.
- Strengthened update validation with HTTPS and strict manifest checks, streamed SHA-256 verification, file-size checks, DMG mounting, Bundle ID/version/build/minimum-system validation, and code-signature verification before installation.
- Restored complete manual update details and localized release-note selection, so manual checks no longer inherit the automatic prompt's two-highlight summary.
- Added release automation that mirrors the same DMG and manifest to Gitee, rejects prereleases from the stable channel, reads version metadata from the DMG itself, serializes manifest publishing, and refuses accidental version downgrades.
- Fixed the Dashboard toolbar update popover closing the entire status panel by deferring the check until presentation is committed and ignoring auxiliary popup windows in the outside-click monitor.
- Made DMG packaging require an explicit stable `VERSION` and positive `BUILD`, preventing stale development defaults from producing an incorrectly versioned installer.
- Reduced CI cost without dropping core coverage by consolidating repetitive update and lifecycle cases into scenario-driven tests and moving translation and diary benchmarks into a separate test target.
