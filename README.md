<p align="center"><img src="Sources/YuanGUI/Resources/AppIcon.png" width="152" alt="YuanGUI icon"></p>

<h1 align="center">YuanGUI</h1>

<p align="center">A native macOS desktop companion with music, system monitoring, AI chat, OCR translation, journaling, and safe cleanup.</p>

<p align="center">
English | <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/YangChen-cn/yuangui/releases/latest">Latest release</a> ·
  <a href="docs/INSTALLATION.md">Installation &amp; permissions</a> ·
  <a href="LICENSE">GPL-3.0-only</a>
</p>

> The screenshots, interface labels, and companion artwork below intentionally use the Chinese interface. YuanGUI itself supports English and Simplified Chinese; choose your language in **Settings → General → Language**, then reopen the app.

## Meet YuanGUI and VCC

YuanGUI is a local-first macOS companion made with SwiftUI, AppKit, and Swift Package Manager. It puts a small companion, useful system information, music, notes, translation, and careful maintenance tools in one native app—without turning your private data into a cloud service.

<!-- GIF placeholder: desktop companion greeting, Chinese interface -->
<!-- ![Desktop companion greeting](docs/media/pet-greeting.gif) -->

## What it includes

| Chinese interface label | What it does |
| --- | --- |
| 桌宠 | Choose YuanGUI, VCC, or both. They react to weather, time, battery, and memory state. |
| 状态面板 | Check CPU, memory, disk, network, battery, uptime, music, and common tools from the menu bar. |
| 音乐 | Control Apple Music, play Bilibili audio, or import local MP3, M4A, AAC, WAV, and AIFF files with playlists, favorites, synchronized lyrics, and desktop lyrics. |
| AI 对话 | Use an OpenAI-compatible endpoint with streaming replies, local history, and your own credentials. |
| 手帐本 | Keep a local journal with photos, Markdown, calendar browsing, backup/restore, and export. |
| 截图翻译 / 划词翻译 | Capture a region, run on-device Vision OCR, translate, edit annotations, or translate selected text. |
| 清理屋 | Review caches, old logs, developer caches, project build artifacts, and old installers before anything changes. |

<!-- GIF placeholder: status panel, Chinese interface -->
<!-- ![Status panel](docs/media/status-panel.gif) -->

## Privacy and cleanup safety

Your journal, chat history, music library, Bilibili tokens, and API credentials stay on this Mac. Attachments are only sent to the AI service you explicitly configure.

Local Music never scans Desktop, Downloads, Documents, Music, your home folder, or any other location on launch. YuanGUI reads audio only after you choose files or folders in the system import panel, stores security-scoped bookmarks for continued access, and leaves the original files untouched. A matching `.lrc` beside an imported track takes priority over the existing lyrics cache and LRCLIB lookup.

Cleanup House is intentionally conservative:

- It never uses `sudo`, changes system settings, resets services, rebuilds Spotlight, scans the whole home folder, or analyzes the entire disk.
- Browser data, developer caches, project artifacts, installers, and inferred orphaned data require review and are not selected by default.
- Project artifacts and installers go to the Trash, never permanent deletion.
- Symbolic links, protected paths, running apps, security/MDM tools, cloud drives, input methods, password managers, AI-model data, and YuanGUI data are skipped.
- Every operation is previewed, confirmed, checked again immediately before execution, and logged locally.

<!-- GIF placeholder: Cleanup House preview, Chinese interface -->
<!-- ![Cleanup House](docs/media/cleanup-house.gif) -->

## Install

Download the DMG from the [latest release](https://github.com/YangChen-cn/yuangui/releases/latest), then drag `YuanGUI.app` to Applications. Personal-share builds use an ad-hoc signature: Control-click the app and choose **Open**, then allow it in **System Settings → Privacy & Security** if macOS blocks it.

Permissions are requested only when you use the related feature:

- **Location** for local weather.
- **Screen Recording** for region capture and OCR translation.
- **Accessibility** for selected-text translation.
- **Music/Finder Automation** after you request music control or a Finder action.
- **Files and folders** only after you explicitly choose local audio to import or relocate.

See the complete [installation and permission guide](docs/INSTALLATION.md), including recovery steps after denying a permission.

## Build from source

```bash
git clone https://github.com/YangChen-cn/yuangui.git
cd yuangui
swift test
./script/build_and_run.sh --verify
./script/package_dmg.sh
```

The package script creates `dist/YuanGUI-2.7.0.dmg`, verifies it, and prints its SHA-256. It keeps the existing ad-hoc signing workflow; a Developer ID and notarization service are optional, not required.

## Contributing

Focused issues and pull requests are welcome. Please run `swift test` before submitting changes. Cleanup rules must remain user-scoped, previewable, and free of elevated privileges.

## License and notices

Source code is licensed under **GPL-3.0-only**, copyright © YangChen-cn. See [LICENSE](LICENSE). Original icons, sprites, character art, and `docs/media` are separately licensed under [CC BY-SA 4.0](ASSET_LICENSE.md). Reused code and acknowledgements are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
