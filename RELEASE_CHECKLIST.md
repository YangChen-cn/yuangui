# 2.7.0 local release checklist

This file records values to apply manually on GitHub. It does not change repository metadata.

- Description: `A native macOS desktop companion with music, system monitoring, AI chat, OCR translation, journaling, and safe cleanup.`
- Topics: `macos`, `swift`, `swiftui`, `appkit`, `macos-app`, `desktop-pet`, `menu-bar-app`, `productivity`, `system-monitor`, `ocr`, `translation`, `mac-cleaner`
- Proposed tag: `v2.7.0`
- Release title: `YuanGUI 2.7.0`
- Upload: `dist/YuanGUI-2.7.0.dmg` and its SHA-256 emitted by `./script/package_dmg.sh`

Before publishing, run `swift test`, `./script/build_and_run.sh --verify`, and `./script/package_dmg.sh`; verify `2.8.2 (21)`, Bundle ID `com.yang.yuangui`, the `YuanGui` self-signed identity, `en.lproj` and `zh-Hans.lproj`, legal documents, and the mounted DMG contents.
