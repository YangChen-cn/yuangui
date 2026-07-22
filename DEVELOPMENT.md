# YuanGUI 接续开发指南

这份文档面向后续维护者和自动化开发代理，记录当前可工作的基线、架构入口、关键约束、验收方式与发布流程。开始修改前先阅读本文件和 `README.md`，再以源码与测试为最终依据。

## 1. 当前基线

| 项目 | 当前状态 |
| --- | --- |
| 默认分支 | `main` |
| 应用版本 | `1.1.2` |
| Build | `10` |
| Bundle ID | `com.yang.yuangui` |
| 最低系统 | macOS 15 |
| 构建方式 | Swift Package Manager，Swift 6 工具链，`swiftLanguageModes: [.v5]` |
| CI 编译环境 | GitHub Actions `macos-26`，因为部分受可用性保护的 API 仍需要 macOS 26 SDK 才能编译 |
| 测试基线 | 160 项执行，2 项网络集成测试默认跳过，0 失败 |
| 许可证 | GPL-3.0-only |

`v1.1.2` 标签位于应用修复提交；README、GPL 和 CI 文档提交在标签之后的 `main` 上。不要仅凭标签判断当前开发文档是否最新。

## 2. 开始工作

```bash
git status --short --branch
git log -8 --oneline --decorate
swift test
```

建议从最新 `main` 创建 `codex/<topic>` 分支进行较大的功能开发。工作区可能已有用户改动，修改前必须先检查状态，不要覆盖无关文件。

这是 SwiftUI/AppKit 图形应用。日常运行请使用项目脚本，不要直接启动 SwiftPM 生成的裸可执行文件：

```bash
./script/build_and_run.sh --verify
```

常用模式：

```bash
./script/build_and_run.sh             # 构建并启动
./script/build_and_run.sh --build-only
./script/build_and_run.sh --verify    # 启动并确认进程存活
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
./script/build_and_run.sh --debug
```

默认使用脚本、单元测试和命令行验收。不要自行使用 Computer Use 做 GUI 自动验收；权限提示、多桌面、窗口拖动和肉眼可读性由用户手动测试。

## 3. 目录与架构

```text
Sources/YuanGUI/
├── App/        # NSApplication 入口和 AppDelegate
├── Models/     # 纯数据模型
├── Services/   # 系统、网络、文件、翻译、音乐和更新服务
├── Stores/     # ObservableObject 状态与业务编排
├── Support/    # NSPanel/NSWindow、布局算法、资源和辅助逻辑
├── Views/      # SwiftUI 视图
└── Resources/  # 图标、精灵和 YuanGUI.Translate.shortcut
```

应用入口是 `Sources/YuanGUI/App/YuanGUIApplication.swift`。`AppDelegate` 长期持有主要 Store 和窗口控制器，并负责：

- 桌宠面板、菜单栏面板和设置窗口；
- AI 对话、维护工具、音乐播放器与歌词面板；
- 快捷工具启动、通知路由和退出前资源清理。

主要子系统：

| 子系统 | 关键文件 |
| --- | --- |
| 桌宠与状态 | `PetStore.swift`、`PetPanel.swift`、`PetRootView.swift`、`SystemMonitor.swift` |
| AI 对话 | `ChatStore.swift`、`AIChatService.swift`、`AISettingsStore.swift`、`ChatView.swift` |
| 音乐与歌词 | `MusicStore.swift`、`BilibiliPlayerEngine.swift`、`AppleMusicController.swift`、`LyricsService.swift` |
| 清理与卸载 | `MaintenanceStore.swift`、`CleanupService.swift`、`SafePathValidator.swift` |
| 截图与标注 | `QuickToolsController.swift`、`ScreenCaptureService.swift`、`ScreenshotEditorWindow.swift` |
| 翻译 | `TranslationEditorStore.swift`、`TranslationPipeline.swift`、`VisionOCRService.swift`、`TranslationEditorWindow.swift` |
| 更新 | `AppUpdateService.swift`、`AboutUpdateView.swift` |

数据流通常保持为：`View → Store → Service`。AppKit 只负责 SwiftUI 不适合处理的窗口、面板、Responder Chain 和系统接口，不要把同一份业务状态同时保存在 SwiftUI 与 AppKit 两侧。

## 4. 截图与翻译管线

默认快捷键定义在 `QuickToolModels.swift`：

- `Control-A`：区域截图；
- `Control-Shift-A`：截图翻译；
- `Control-Z`：划词翻译。

快捷键可以由用户修改，不能在调用处重复硬编码。

截图翻译主流程：

```text
QuickToolsController
  → CaptureSelectionController
  → ScreenCaptureService
  → VisionOCRService
  → OCRLayoutAnalyzer
  → TranslationEditorStore / TranslationPipeline
  → System Shortcut / Apple local / Online AI
  → ScreenshotTranslationLineAligner
  → ScreenshotTranslationLayoutEngine
  → ScreenshotTranslationOverlayWindow
```

必须保持的行为约束：

1. OCR 视觉行先组织为语义句子或段落，再批量翻译；不要恢复成逐行网络请求。
2. 系统快捷指令可使用内部序号对齐结果，但任何内部标记都必须在显示前清理。
3. 只有整行都是 URL、邮箱或纯数字时才跳过翻译；包含 URL 的正常句子仍要翻译。
4. 覆盖译文必须保持原 OCR 文本框的横向锚点，不能借用右侧无关控件区域或漂移到其他列。
5. 布局允许在同列安全空白内增加高度；相邻句子之间不能重叠。
6. 译文必须完整显示，不使用省略号；极端长文本允许降到 7pt，但有空间时应尽量放大。
7. 截图翻译覆盖层支持缩放、中英对照、复制、拖动和 `Esc` 关闭，并停留在触发时的桌面 Space。
8. 普通翻译窗口是单实例。每次呼出新窗口前必须显式关闭旧 `NSPanel`；仅把控制器引用设为 `nil` 不会关闭 AppKit 保留的窗口。
9. 旧窗口的延迟关闭回调不能清空新窗口引用，`QuickToolsController` 当前使用 presentation ID 防止该竞态。
10. 普通翻译窗口记忆用户宽度，只随内容调整高度；拖动或实时缩放期间不要触发自适应，避免窗口抖动。

`TranslationPipeline` 是 actor，负责相同请求合并、任务取消和内存 LRU 缓存。默认缓存上限为 100 项、约 5 MB、10 分钟；不要把截图、OCR 或译文缓存写入磁盘。

划词读取的降级路径位于 `AccessibilityTextService.swift`。修改时要同时考虑辅助功能选区、Safari/Chrome/Edge 网页、复制选区和无文本时手动输入。替换原文前必须再次校验应用、控件与选区快照，不能把译文写入已经变化的位置。

## 5. 权限、路径与资源

功能可能涉及：

- 屏幕录制：区域截图、截图 OCR；
- 辅助功能：读取或替换选中文字、模拟复制；
- 位置：天气；
- Apple Events：Music 与 Finder 操作；
- Shortcuts/Apple 翻译：默认免费翻译引擎。

权限是否成功不能只在开发电脑上判断。另一台 Mac 可能已有旧 Bundle 权限记录，需要移除旧条目后重新添加当前应用。

路径与资源规则：

- 禁止写死 `/Users/<name>/...`。截图默认目录由 `FileManager.default.homeDirectoryForCurrentUser` 动态生成。
- SwiftPM 资源在开发环境使用 `Bundle.module`，打包后必须从应用资源目录读取；不要保存 `.build/...` 的绝对路径。
- `YuanGUI.Translate.shortcut` 必须随 SwiftPM resource bundle 一起复制到 `.app`。
- API Key 使用 `LocalSecretStore` 的仅当前用户可读文件，不依赖 Apple 钥匙串。
- 用户已有数据和设置属于用户，迁移时保持向后兼容。

## 6. 测试与性能

完整测试：

```bash
swift test
```

翻译性能报告：

```bash
./script/benchmark_translation.sh
```

测试分布：

- `QuickToolsTests.swift`：截图、OCR、翻译、窗口与随机布局属性测试；
- `TranslationBenchmarkTests.swift`：离线 JSON 性能报告；
- `Fixtures/screenshot-layout-fixtures.json`：网页、邮件、列表、多列、深色和密集文本布局夹具；
- 其余测试文件按 AI、音乐、天气、系统指标、桌宠、维护和更新子系统划分。

两个 Bilibili 网络测试默认跳过，只有显式设置环境变量时才运行：

```bash
YUANGUI_LIVE_BILI=1 swift test
YUANGUI_LIVE_BILI_SUBTITLES=1 swift test
```

GitHub Actions 位于 `.github/workflows/tests.yml`，每次 push、Pull Request 和手动触发时运行 `swift test`。CI 使用 `macos-26` SDK 编译，但 `Package.swift` 的最低部署目标仍是 macOS 15；不要为了 CI 方便把最低系统版本改成 26。

截图翻译改动至少要覆盖以下回归条件：

- 无文本框重叠；
- 无省略号；
- 字体不低于 7pt；
- 文本框不越过截图边界；
- 无内部标记泄漏；
- URL 混排句子仍会翻译；
- 同一句的视觉换行不会被错误拆成无关段落；
- 重复呼出翻译窗口不会累积多个窗口。

## 7. 本地构建和人工验收

推荐命令：

```bash
swift test
./script/build_and_run.sh --verify
```

脚本验收后，由用户手动检查：

- 首次权限请求和另一台 Mac 的权限迁移；
- Safari、Chrome、Edge 和普通可编辑应用中的划词；
- 翻译窗口单实例、拖动、缩放和长文本高度；
- 截图翻译在邮件、网页、多列、小控件、深色背景和 Retina 截图上的可读性；
- 工具条跟随、`Esc` 关闭、中英对照开关与多桌面行为；
- Bilibili 手动切歌后的选中状态与歌词匹配。

## 8. 打包与发布

生成 DMG：

```bash
./script/package_dmg.sh
```

默认产物为临时签名的个人分享版：

```text
dist/YuanGUI-<version>.dmg
```

Developer ID 签名与公证：

```bash
SIGNING_IDENTITY="Developer ID Application: ..." \
NOTARY_PROFILE="your-notary-profile" \
./script/package_dmg.sh
```

发布新版本时需要同步检查：

1. `Sources/YuanGUI/Services/AppUpdateService.swift` 的 fallback version、build 和本版摘要；
2. `script/build_and_run.sh` 的 `CFBundleShortVersionString` 与 `CFBundleVersion`；
3. `script/package_dmg.sh` 的默认 `VERSION` 与 build；
4. `README.md` 的下载文件名、安装命令、测试数量和产物路径；
5. `RELEASE_NOTES.md`；
6. 全量 `swift test`；
7. DMG 内的版本、Bundle ID、签名、镜像校验和 SHA-256；
8. 推送 `main`、创建版本标签、上传 Release 资产后再次读取 GitHub 元数据确认。

不要随意移动已经发布的 Git tag。只有用户明确要求覆盖同一版本时，才可以更新标签或使用 `gh release upload --clobber` 替换同名 DMG；这种情况下不要擅自修改 Release notes。

## 9. 常见问题

### CI 找不到 macOS 26 API

`#available(macOS 26, *)` 只能处理运行时可用性，编译时仍需要包含该符号的 SDK。CI 因此使用 `macos-26` runner，而不是 `macos-15`。

### 其他电脑打开快捷工具崩溃

优先检查是否读取了开发机 `.build` 目录或写死用户路径。发布版只能依赖应用包资源和当前用户动态目录。

### 翻译窗口越开越多

`NSPanel.isReleasedWhenClosed` 为 `false` 时，释放 Swift 控制器引用不会关闭窗口。展示新翻译窗口前要调用 `close()`，并保留窗口生命周期回归测试。

### 截图译文跑到右侧控件或出现省略号

检查 OCR 语义分组、句子 ID 回填和布局锚点。不要通过向右扩框或合并无关列来解决空间不足；应优先使用同列上下空白、自适应字号和完整换行。

### 拖动窗口抖动

不要让主窗口和工具条互相反向更新坐标。工具条应作为父子窗口关系跟随；拖动期间暂停自动布局，结束后只做一次屏幕边界校正。

## 10. 提交前检查

```bash
git diff --check
swift test
git status --short --branch
```

提交说明应描述一个可独立回退的改动。不要把版本发布、OCR 算法、窗口交互和无关清理混在同一个提交中。
