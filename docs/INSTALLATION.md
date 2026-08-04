# Install and permissions

[简体中文](INSTALLATION.zh-CN.md)

## Install the DMG

1. Download the DMG from the [latest release page](https://github.com/YangChen-cn/yuangui/releases/latest).
2. Open it and drag `YuanGUI.app` to `Applications`.
3. This project currently uses an ad-hoc signature for local/personal distribution. Control-click the app, choose **Open**, then confirm.
4. If Gatekeeper still blocks it, open **System Settings → Privacy & Security** and choose **Open Anyway** for YuanGUI.

YuanGUI supports macOS 15 or later. Do not launch the bare SwiftPM executable for regular use; package the app with `./script/build_and_run.sh --verify` or install the DMG.

## Enable the Finder context menu

1. Launch the packaged YuanGUI app once.
2. Open **YuanGUI Settings → Quick Tools → Finder Context Menu Extension**.
3. Choose **Open Extension Settings**.
4. In **System Settings → General → Login Items & Extensions**, enable **YuanGUI Finder Extension**.

The extension adds file creation, Copy Path, Open in Terminal, and menu-only Cut/Paste to the desktop and local Finder locations. It does not scan folders on launch. iCloud Drive, OneDrive, and other File Provider locations are not guaranteed in this first version.

## Permission recovery

| Permission | Why it is requested | Restore it after denial |
| --- | --- | --- |
| Screen Recording | Captures only an area you explicitly select for screenshot OCR/translation. | System Settings → Privacy & Security → Screen Recording → enable YuanGUI, then reopen it. |
| Accessibility | Reads selected text and can replace text only after you request translation. | Privacy & Security → Accessibility → enable YuanGUI, then retry the shortcut. |
| Location | Shows approximate local weather; no location trail is stored. | Privacy & Security → Location Services → enable YuanGUI. |
| Automation (Music) | Controls the system Music app after you choose Apple Music playback. | Privacy & Security → Automation → enable YuanGUI → Music. |
| Automation (Finder) | Asks Finder to move explicitly selected cleanup items to the Trash. | Privacy & Security → Automation → enable YuanGUI → Finder. |

If a feature does not prompt again, quit YuanGUI, adjust the permission in System Settings, and reopen it. For Screen Recording and Accessibility, reopening is normally required by macOS.

## Cleanup boundaries

Cleanup does not use administrator privileges. It does not scan your entire home directory, modify system directories, reset services, rebuild Spotlight, or perform system optimization. You can inspect every candidate, whitelist it, and review the local operation history before any item is removed.
