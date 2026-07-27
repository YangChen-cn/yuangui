<p align="center"><img src="Sources/YuanGUI/Resources/AppIcon.png" width="152" alt="元圭与 VCC 图标"></p>

# 元圭与 VCC

原生 macOS 桌宠与效率工具：音乐、系统监控、AI 对话、OCR 翻译、日记和安全清理。

<p align="center">
<a href="README.md">English</a> | 简体中文
</p>

<p align="center">
  <a href="https://github.com/YangChen-cn/yuangui/releases/latest">最新发布页</a> ·
  <a href="docs/INSTALLATION.zh-CN.md">安装与权限说明</a> ·
  <a href="LICENSE">GPL-3.0-only</a>
</p>

YuanGUI 使用 SwiftUI、AppKit 与 Swift Package Manager 开发。个人数据默认留在本机；只有使用相关功能时才会请求系统权限。

## 主要功能

- 元圭、蓝猫 VCC 与双人模式桌宠，结合天气、时间、电池和内存状态互动。
- 菜单栏状态面板：CPU、内存、磁盘、网络、电池、运行时间、音乐和常用工具。
- 本地日记：照片、Markdown、日历、备份恢复和导出。
- Apple Music 控制、哔哩哔哩播放与导入，以及 MP3、M4A、AAC、WAV、AIFF 本地音乐；支持歌单、收藏、同名 LRC、歌词缓存和桌面歌词。
- 兼容 OpenAI 接口的流式 AI 对话、本地历史和可编辑角色提示词。
- 区域截图、端侧 Vision OCR、截图翻译、划词翻译与标注。
- 清理屋：缓存、旧日志、开发缓存、项目构建产物和旧安装包的保守扫描。

## 清理安全

- 不使用 sudo，不优化系统、不重置服务、不重建 Spotlight，不扫描整个主目录或整盘大文件。
- 浏览器、开发缓存、项目产物、安装包和推断出的孤儿数据都需要人工检查，默认不选。
- 项目产物和旧安装包只会移入废纸篓，不会永久删除。
- 符号链接、保护目录、运行中应用、系统/安全/MDM 软件、云盘、输入法、密码管理器、AI 模型和 YuanGUI 数据自动跳过。
- 每项操作均可预览、再次确认、执行前复核并写入本地记录。

## 本地音乐与隐私

YuanGUI 不会在启动或打开音乐页时扫描桌面、下载、文稿、音乐、用户主目录或其他位置。只有点击“导入音乐”并在系统面板中选择文件或文件夹后，应用才会读取其中受支持的音频；递归查找仅限用户选中的文件夹。应用使用安全作用域书签延续访问权限，不复制、移动或修改原始音乐文件。音频旁的同名 `.lrc` 会优先于现有歌词缓存和 LRCLIB。

菜单栏音乐空态会显示当前来源对应的操作，并始终提供“打开完整播放器”入口。完整播放器中的导入按钮会随侧栏宽度自动排列，不截断标签；资料库内建名称随应用语言显示，用户自己的歌单名和歌曲信息保持原样。

## 安装与构建

请在[最新发布页](https://github.com/YangChen-cn/yuangui/releases/latest)下载 DMG，将 `YuanGUI.app` 拖入“应用程序”。个人分享版使用临时签名；若首次被拦截，请按住 Control 点击“打开”，或在“系统设置 → 隐私与安全性”中允许。

完整权限恢复步骤见[安装与权限说明](docs/INSTALLATION.zh-CN.md)。从源码验证：

```bash
swift test
./script/build_and_run.sh --verify
./script/package_dmg.sh
```

## 许可

代码采用 **GPL-3.0-only**，版权 © YangChen-cn，见 [LICENSE](LICENSE)。图标、Sprites、角色图和 `docs/media` 独立采用 [CC BY-SA 4.0](ASSET_LICENSE.md)。复用代码和服务致谢见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
