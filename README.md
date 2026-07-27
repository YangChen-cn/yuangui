<p align="center"><img src="Sources/YuanGUI/Resources/AppIcon.png" width="152" alt="YuanGUI icon"></p>

# YuanGUI

A native macOS desktop companion with music, system monitoring, AI chat, OCR translation, journaling, and safe cleanup.

[简体中文](README.zh-CN.md) · [Latest release](https://github.com/YangChen-cn/yuangui/releases/latest) · [Installation and permissions](docs/INSTALLATION.md)

YuanGUI is built with SwiftUI, AppKit, and Swift Package Manager. It keeps personal data local by default and asks for system permissions only when the relevant feature is used.

## Highlights

- Desktop companions: YuanGUI, VCC, or both, with weather, time, battery, and memory-aware reactions.
- A compact status panel for CPU, memory, disk, network, battery, uptime, music, and common tools.
- Local-first journal with photos, Markdown, calendar, backup/restore, and export.
- Apple Music controls, Bilibili playback/import, local lyrics, and optional desktop lyrics.
- OpenAI-compatible AI chat with streaming, local history, and user-controlled API credentials.
- Region capture, on-device Vision OCR, screenshot translation, selected-text translation, and editable annotations.
- A conservative Cleanup House: reviewable caches, old logs, developer caches, project build artifacts, and old installers.

## Safety and privacy

- Cleanup never uses `sudo`, modifies system settings, resets services, rebuilds Spotlight, scans the whole home directory, or analyzes the entire disk.
- Browser data, developer caches, project artifacts, installers, and inferred orphaned data are review-only and are not selected by default.
- Project artifacts and old installers are moved to the Trash, never permanently deleted.
- Protected paths, symbolic links, running apps, system/MDM/security software, cloud storage, input methods, password managers, AI-model data, and YuanGUI data are skipped.
- Every operation is previewed, reconfirmed, checked again immediately before execution, and recorded locally.
- Chat history, journal entries, Bilibili tokens, and API credentials remain on this Mac. AI attachments are sent only to the service you configure.

## Requirements

- macOS 15 Sequoia or later
- Swift 6 / current Xcode for source builds
- Your own compatible API URL and key for AI chat

## Install

Open the [latest release page](https://github.com/YangChen-cn/yuangui/releases/latest), download its DMG, and drag `YuanGUI.app` to Applications. Personal-share builds use an ad-hoc signature: Control-click the app and choose **Open**, then approve it in **System Settings → Privacy & Security** if macOS blocks it.

See the complete [installation and permission guide](docs/INSTALLATION.md), including Screen Recording, Accessibility, Location, Music/Finder Automation, and recovery after denying a permission.

## Build from source

```bash
git clone https://github.com/YangChen-cn/yuangui.git
cd yuangui
swift test
./script/build_and_run.sh --verify
./script/package_dmg.sh
```

The package script creates `dist/YuanGUI-2.7.0.dmg`, verifies the image, and prints its SHA-256. It keeps the existing ad-hoc signing workflow; it does not require a Developer ID or notarization service.

## Localization

YuanGUI ships English and Simplified Chinese. Open **Settings → General → Language**, choose System, English, or Simplified Chinese, then quit and reopen the app. Existing user content, chat history, library data, file formats, and persisted enum values are unchanged.

## Contributing

Please open an issue or pull request with a focused change and tests where practical. Run `swift test` before submitting. Do not add cleanup rules that require elevated privileges or can affect system data without explicit review and tests.

## License and notices

YuanGUI source code is licensed under **GPL-3.0-only**, copyright © YangChen-cn. See [LICENSE](LICENSE). Original icons, sprites, character art, and `docs/media` are separately licensed under [CC BY-SA 4.0](ASSET_LICENSE.md). Reused code and acknowledgements are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
