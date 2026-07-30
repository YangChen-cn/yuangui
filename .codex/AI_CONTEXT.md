# YuanGUI 新 AI 聊天接续上下文

> 用途：这是项目所有者写给后续 AI 聊天的本地上下文，不是公开开发者文档。
> 本文件位于通常被 `.gitignore` 排除的 `.codex/` 目录；本次用户明确要求“git 保存”，因此随本次提交保留。后续若用户未明确要求，不要默认提交它。

## 新聊天开始时先做什么

请先执行只读检查，再开始修改：

```bash
git status --short --branch
git log -8 --oneline --decorate
sed -n '1,260p' .codex/AI_CONTEXT.md
sed -n '1,260p' README.md
```

以当前源码、测试和用户最新消息为准。本文件用于快速理解背景；如果内容与代码冲突，应先核对代码并更新本文件。

## 与用户协作的硬性约束

1. 默认使用中文沟通，先给结果，再简要说明验证情况。
2. 修改功能时直接实施，不要反复让用户确认可以从代码中自行判断的细节。
3. 验收先运行脚本、命令行和单元测试；测试通过后，默认执行 `./script/build_and_run.sh --verify` 构建并启动最新 `.app`。
4. 默认不要使用 Computer Use 或 GUI 自动点击；脚本和测试完成后由用户手动验收界面。只有用户在当前任务中明确要求自动操作界面时才使用相关工具。
5. GUI 验收应优先覆盖本次修改直接影响的页面和交互。权限弹窗、多桌面、窗口拖动、截图翻译肉眼可读性、浏览器划词和替换原文等环境依赖项目，无法稳定自动验证时再交由用户手动测试。
6. 只有实际观察到的 GUI 状态才能报告为通过；未能自动覆盖的项目应明确列为人工测试重点。
7. 不要默认启用付费在线 AI。翻译默认保持免费的系统快捷指令；在线 AI 只有用户明确选择并完成配置后才使用。
8. 不要把个人使用无关紧要的问题当成主要工作，例如强制改用 Apple 钥匙串、要求正式 Developer ID 签名或公证。除非用户明确要求，否则保留当前本地密钥文件和个人分享版临时签名方案。
9. 不要写死用户名、桌面、图片或构建目录。所有用户路径必须通过 `FileManager` 或系统 API 动态获取。
10. 不要依赖开发机 `.build` 绝对路径读取资源；发布版资源必须从应用包或 SwiftPM resource bundle 获取。
11. 先检查工作区，保留用户已有改动。不要使用 `git reset --hard`、`git checkout --` 等破坏性命令清理文件。
12. Git 提交、推送、修改标签、创建 Release 或替换 DMG，应以用户当前请求为准；不要把普通代码修改自动扩大成发布任务。
13. 用户要求覆盖同一 Release 时，只做其明确要求的内容。例如“只覆盖 DMG”就不要改 Release notes。
14. 删除、覆盖、强制更新标签或其他难恢复操作前，要确认目标与用户要求完全一致。

## 当前项目基线

| 项目 | 当前状态 |
| --- | --- |
| 项目 | 元圭与 VCC / YuanGUI |
| 默认分支 | `main` |
| 当前应用版本 | `2.7.0` |
| Build | `16` |
| Bundle ID | `com.yang.yuangui` |
| 最低系统 | macOS 15 |
| 构建方式 | SwiftPM，Swift 6 工具链，源码使用 Swift 5 language mode |
| CI | GitHub Actions `macos-26` runner，执行 `swift test`，SwiftPM `.build` 使用 `actions/cache@v5` 缓存 |
| 测试基线 | 333 项执行，2 项网络测试默认跳过，0 失败 |
| 许可证 | GPL-3.0-only |

CI 使用 macOS 26 SDK 是因为 `WeatherService.swift` 中有受 `#available(macOS 26, *)` 保护的新 MapKit API。应用最低部署版本仍然是 macOS 15，不要为了 CI 把最低版本改成 26。

状态面板默认使用 Liquid Glass 主题：macOS 26 及以上通过受可用性保护的 SwiftUI `glassEffect` 与 `GlassEffectContainer` 呈现原生效果；macOS 15–25 使用系统 Material 降级，不改变最低部署版本。

2026-07-25 的原生 Liquid Glass 实验保存在 `liquid-glass` 分支（起点包含 `4b484cc` 与后续 `26a2cfa`）。实验分支中，macOS 26 的番茄钟、状态栏 Footer 开关和音乐主控优先使用系统 `.glass` / `.glassProminent` 按钮；非运行状态的中性按钮必须显式清除继承 tint 并使用 `.primary` 前景，避免亮色桌面上出现白字低对比。页面导航只有选中标签使用固定高度的交互玻璃，不再保留整块人工灰色底板。状态面板外层是一块原生 `regular` 玻璃，天气与正在播放等内容区仅用低透明语义底色分组，避免玻璃套玻璃。背景环境色受角色、智能状态、主题、深色模式和增强对比度约束。现有 NSPanel 继续承担动态页面高度、状态栏锚定、跨 Space、点击外关闭和首击稳定性；未直接替换为 `MenuBarExtra` 或 `NSPopover`。

2026-07-29 的 2.7.0 发布提交为 `2bdee5c`；当前本地 `main` 在其上新增了清理台 UI、更新说明资产拉取和 CI 缓存提交，远端尚未同步。当前应用版本为 2.7.0（Build 16），最近一次本地全量测试为 333 项通过、2 项网络测试跳过。

Liquid Glass 页签的选中玻璃必须直接修饰固定高度标签，不能把无固有尺寸的透明 `RoundedRectangle` 作为 `ZStack` 子视图再应用 `glassEffectID` / matched geometry；后者在 NSPanel 的弹性提案下会被拉伸并挤掉页面内容。导航总高度由 `DashboardDesign.navigationHeight` 控制，`NSHostingView` 回归测试要求固有高度不超过 44pt。工具页品牌入口可以在同一个 `GlassEffectContainer` 中使用交互玻璃；普通控制保持中性玻璃，仅真正主操作使用强调色。

桌宠浮层统一复用 `YuanLiquidGlass.swift`：状态气泡和主动对白在 macOS 26 使用适合丰富桌面背景的 `.clear` 玻璃，气泡尾部加入同一 `GlassEffectContainer`；迷你监控使用单一 `.clear` 玻璃；迷你播放器使用 `.regular` 玻璃与原生玻璃按钮。macOS 15–25 自动降级为单层 `regularMaterial`。不要重新叠加白色渐变、白色描边、多层 Material 或大阴影，否则会遮断系统玻璃的采样、折射与可访问性适配。

主题升级使用一次性 `dashboardStyleLiquidGlassMigrationV1` 标记：第一次运行含该迁移的版本时，即使旧用户保存了其他面板主题，也改为 Liquid Glass；之后用户再次主动选择樱花、薄荷等主题时必须保留，不能每次启动都覆盖。

桌宠音乐气泡与本体播放角标统一走 `PetMusicPresentationPolicy`。歌词气泡显示时必须隐藏本体右上角的独立粉色音符，避免两个提示重叠；无同步歌词或关闭轻量跟唱时仍可显示独立播放角标。桌面歌词主体使用无 Material、无 Glass 的浅一些半透明细条，默认不透明度 24%，允许在桌面歌词设置与音乐设置中于 12%–60% 调节；降低主歌词阴影并明显压低副歌词亮度。仅关闭、锁定、设置等控制按钮共享 `GlassEffectContainer`。“背景”开关只额外增强细条对比度。

桌宠打开 AI 对话前必须记录 compact 面板的精确 origin，关闭时优先原点恢复；不要只用角色视觉 frame 反推位置，也不要用完整面板边界约束破坏靠屏幕边缘时合法的透明区域越界。位置快照必须通过 `ChatStore.onWillPresentationChange` 在写入 `isPresented` 之前同步完成，不能等 Combine/SwiftUI 收到状态后再取 `panel.frame`，因为此时 AppKit 可能已经按聊天内容调整了窗口。关闭时即使 AppKit 已先把 panel 缩成目标尺寸，也必须继续执行原点恢复，不能因尺寸相同提前返回。`PetLayout.restoredCompactOrigin` 仅在角色本体不足 44pt 可见时才收回屏幕。`PetPanel.constrainFrameRect` 和控制器主动约束都必须使用 `compactHorizontalOverflow`，允许角色左右两侧的透明留白留在屏幕外。`NSWindow.didMoveNotification` 的程序化移动标记必须在通知回调中同步捕获，避免异步 MainActor 任务把聊天展开后的临时位置误存为用户位置。

桌面歌词字体不能只把所有选项映射为一个模糊的系统 design。系统圆体、默认、衬线、等宽使用 `Font.system`，中文苹方、宋体、楷体、黑体分别使用 `PingFang SC`、`Songti SC`、`Kaiti SC`、`Heiti SC`，旧的 raw value 必须保持兼容。

低电量分级为：11%–20% 显示含具体百分比的限时主动气泡，并在仍处于该区间时每 5 分钟重复；10% 及以下才进入常驻紧急提醒。重复提醒使用已有系统快照，不新增采样定时器。

## 常用命令

全量测试：

```bash
swift test
```

默认完成流程：

```bash
swift test
./script/build_and_run.sh --verify
```

测试通过后默认构建 `.app`、启动并确认进程；界面修改再使用 GUI 工具检查本次受影响的页面与交互。

构建、生成 `.app`、启动并验证进程：

```bash
./script/build_and_run.sh --verify
```

只构建应用包：

```bash
./script/build_and_run.sh --build-only
```

翻译离线性能报告：

```bash
./script/benchmark_translation.sh
```

生成并验证 DMG：

```bash
./script/package_dmg.sh
```

这是 SwiftUI/AppKit GUI 应用，不要把 SwiftPM 生成的裸可执行文件当作正常运行方式。

## 恋爱手账实现基线

恋爱手账已经从原型整理为独立的 SwiftUI/AppKit 功能域。后续修改优先保持下面的状态和边界：

- `Sources/YuanGUI/Stores/DiaryFeature.swift`：`@MainActor` 的界面状态协调器，负责一次性加载、筛选、选择、`DiaryDraft` 编辑、脏记录、自动保存、退出前 `flush()`、导出和桌宠保存完成回调。每篇脏记录带单调递增修订号，保存完成只能清除开始保存时的版本；等待期间出现新编辑时，`flush()` 必须继续保存到状态稳定。`loadIfNeeded()` 防止重复打开窗口时从磁盘覆盖内存编辑内容；`reloadFromDisk()` 必须先保存。
- `Sources/YuanGUI/Services/DiaryRepository.swift`：`actor`，串行管理条目文件、附件关联的删除流程和最近删除。保存使用 `DiaryFileEnvelope`（当前格式版本为 1），兼容读取旧的裸 `DiaryEntry` JSON；单个损坏文件会移到 `Recovery/CorruptEntries/`，不阻塞其他条目加载。
- `DiaryStorageLayout` 支持注入临时根目录。生产目录位于动态取得的 Application Support 下，目录结构为 `Entries/`、`Attachments/Originals/`、`Attachments/Thumbnails/`、`Recovery/` 和 `RecentlyDeleted/`；备份目录在日记根目录外。测试不得访问生产目录。
- `Sources/YuanGUI/Services/DiaryAttachmentStore.swift`：图片导入、缩略图、校验和清理均在 actor 中执行。每篇最多 20 张、单张最多 20 MB、最多 50 MP，允许 JPEG、PNG、HEIC/HEIF、WebP 和 GIF；附件文件名使用 UUID，原图与缩略图分目录保存。
- `Sources/YuanGUI/Services/DiaryExportService.swift`：集中处理 Markdown、带版本 JSON、ZIP 导出以及完整备份恢复。备份包含 manifest、相对目录结构、SHA-256 和格式版本；恢复必须先验证候选数据，再替换当前目录，失败时保留或回滚当前数据。
- `Sources/YuanGUI/Services/DiaryAutoBackupService.swift`：日记成功落盘后每天最多自动备份一次，保留最近 7 个每日归档和 4 个每周归档；立即备份使用独立文件，不参与自动保留裁剪。设置页“手帐本”显示上次自动备份、数量，并提供打开文件夹、立即备份和恢复入口。
- `Sources/YuanGUI/Views/Diary/DiaryMainView.swift`：主界面使用三栏 `NavigationSplitView`，侧栏管理视图和筛选，中栏显示时间线，右栏显示编辑器、日历、照片墙、那年今日或最近删除。月份、日期、标签、收藏和搜索统一由 `DiaryFilter` 管理，搜索有 250ms 防抖。
- `Sources/YuanGUI/Views/Diary/DiaryDetailEditView.swift`：完整日记使用 `DiaryDraft` 按字段编辑；日期只显示记录时间，心情位于日期右侧，“那一刻”相关元数据位于标题区域上方；支持 Markdown 编辑/预览、照片拖放、`NSOpenPanel` 多选和剪贴板粘贴。图片 Command-V 由正文专用 `DiaryTextView.paste(_:)` 处理，不得恢复窗口级键盘监听，以免吞掉标题、地点和标签的普通粘贴。
- `Sources/YuanGUI/Views/Diary/QuickDiaryEntryView.swift`：桌宠底栏打开快速记录窗口，不打开完整日记。快速记录在打开时固定当前时间、天气和音乐快照，支持心情、地点、标签和照片，并可通过“完整编辑”回到主日记窗口。
- 地点优先读取已有天气定位结果，读取后仍可直接编辑。音乐只有在当前播放状态为 `isPlaying == true` 且存在有效曲目时才写入日记；暂停或停止不记录音乐。
- `Sources/YuanGUI/Support/DiaryWindowController.swift`：保留单实例完整日记窗口和独立快速记录窗口。完整窗口首次关闭请求会等待异步保存，保存失败提供重试或关闭选项；AppDelegate 的正常退出、更新退出和系统注销/关机路径应继续调用日记 `flush()`。
- `Sources/YuanGUI/Stores/PetStore.swift`：日记自动保存不触发桌宠反馈；完整编辑结束、切换条目、关闭窗口或快速记录明确保存后才提示一次。元圭、VCC、一起模式使用各自独立的保存台词。

恋爱手账后续改动的关键人工验收项：空日记时搜索框和空状态不得重叠；照片栏缩略图应完整显示并可在未打开查看器时缩放预览；快速记录和完整编辑的心情、地点、那一刻、音乐状态一致；桌宠底栏进入快速记录，菜单栏进入完整日记；窗口关闭必须等待保存；拖放、剪贴板、Save Panel、Command-Z 和原图查看仍交由用户做 GUI 验收。

日记专项测试覆盖格式迁移、损坏隔离、脏记录和部分保存失败、保存期间继续编辑、退出/编辑完成反馈、音乐播放状态、附件限制和清理、月份/日期/那年今日跳转以及三种桌宠台词。最近一次在 `liquid-glass` 的全量测试执行 283 项（2 项网络测试跳过），0 失败。

## 架构入口

- `Sources/YuanGUI/App/YuanGUIApplication.swift`：轻量 AppDelegate、`AppRuntime` 依赖组装和 `WindowCoordinator` 单实例窗口生命周期。
- `Sources/YuanGUI/App/AppRouting.swift`：类型安全 `AppRoute`、快捷工具路由和 SwiftUI 环境动作。
- `Sources/YuanGUI/Stores/PetStore.swift`：桌宠状态、天气与系统监控。
- `Sources/YuanGUI/Stores/MusicFeature.swift`：非 Observable 的音乐组合入口与跨域协调。
- `Sources/YuanGUI/Stores/MusicFeatureStores.swift`：播放、资料库、歌词、歌词呈现、Bilibili 账号和导入六个可观察子 Store。
- `Sources/YuanGUI/Stores/QuickToolsController.swift`：截图、截图翻译、划词翻译和全局快捷键编排。
- `Sources/YuanGUI/Stores/TranslationEditorStore.swift`：普通翻译窗口状态和翻译任务。
- `Sources/YuanGUI/Services/TranslationPipeline.swift`：请求合并、取消和内存缓存。
- `Sources/YuanGUI/Services/VisionOCRService.swift`：本地 Vision OCR。
- `Sources/YuanGUI/Support/OCRLayoutAnalyzer.swift`：OCR 去重、视觉行、段落和阅读顺序。
- `Sources/YuanGUI/Support/ScreenshotTranslationLayoutEngine.swift`：截图译文布局。
- `Sources/YuanGUI/Support/ScreenshotTranslationOverlayWindow.swift`：覆盖层、工具条、缩放、中英对照和多桌面行为。
- `Sources/YuanGUI/Services/AccessibilityTextService.swift`：划词读取和替换原文。
- `Sources/YuanGUI/Services/AppUpdateService.swift`：GitHub Release 检查、DMG 校验和应用替换。

整体数据流通常为：`SwiftUI View → Observable Store → Service`。窗口操作由 SwiftUI 环境中的 `AppActions` 路由到 `WindowCoordinator`，不要恢复 YuanGUI 自定义 `NotificationCenter` 通知；AVPlayer、NSWindow、NSWorkspace 等系统通知可以保留。AppKit 主要处理 `NSPanel`、`NSWindow`、Responder Chain 和系统接口，不要在 SwiftUI 与 AppKit 两边复制业务状态。

`ChatStore.send()` 必须在发送前捕获目标会话 ID，并将用户消息、请求上下文、流式文本、最终回复和错误绑定到该 ID；等待期间切换或删除会话不得把结果写进当前会话。`loadSessionIfNeeded()` 不得跨 `await` 保存数组下标，返回后必须重新按 ID 定位，并放弃已删除或已在内存中更新的会话结果。

音乐“接下来播放”由 `MusicPlaybackCoordinator` 持有的 `MusicPlaybackQueue` 统一管理，并发布到 `MusicPlaybackStore`。随机模式必须先生成稳定顺序，再由“下一首”和界面共同消费；不要在视图中另算队列，也不要在每次切歌时临时 `randomElement()`，否则显示顺序会和实际播放不一致。单曲循环只显示当前歌曲，顺序和列表循环按真实后续顺序展示。

外部音频自动暂停默认关闭，以一次连续外部音频为一个会话：只有会话开始后未被用户手动覆盖时才可自动暂停/恢复。外部声音已存在时，用户主动播放、暂停、切歌或拖动进度均视为覆盖，允许并行播放并取消恢复资格；会话稳定结束后才清除覆盖状态。监测优先监听 Core Audio 的进程列表和 `kAudioProcessPropertyIsRunningOutput` 事件，0.5 秒轮询仅作兜底。

桌宠的状态、天气、歌词气泡由独立 `PetAuxiliaryBubblePanel` 承载，不能再通过改变主 `PetPanel` 高度来显示临时气泡。内容布局不得写回用户保存位置；聊天和维护确需调整主体尺寸时要保持角色图像底部中心锚点。靠屏幕边缘打开聊天时，必须在 `ChatStore.isPresented` 改变前同步保存 compact 面板原点，关闭时恢复该原点；即使 AppKit 已提前缩小窗口也不能提前返回。聊天期间用户主动拖动则更新恢复位置。

动作统一走 `PetActionResolver`：维护/完成、聊天、紧急状态、专注、10 秒非紧急新状态、听歌、对白/手动/待机依次降级。持续下雨等状态不能反复重启计时并永久覆盖听歌。

低电量状态分级由 `BatteryAlertLevel` 决定：`11%...20%` 是 warning，显示含具体百分比的限时气泡，并在仍处于该区间时每 5 分钟重复，不进入常驻迷你状态；`<=10%` 才是 critical，并始终常驻。充电中或无电池 Mac 始终为 normal。电量跨越 10% 时即使 `SmartPetState` 仍是 `.lowBattery`，也必须触发一次状态重新评估。

## 快捷工具现状

默认快捷键：

- `Control-A`：区域截图；
- `Control-Shift-A`：截图翻译；
- `Control-Z`：划词翻译。

用户可以在设置中修改快捷键，因此调用处不要重复硬编码。

翻译引擎：

1. 系统快捷指令：默认，免费调用 Apple 翻译；
2. Apple 本地翻译：可能需要下载系统语言资源；
3. 在线 AI：只在用户主动选择时使用配置好的兼容 API。

划词没有取得文字时仍要打开手动输入窗口。原文可以编辑后重新翻译；“替换原文”写回的是译文，但写回前必须校验原应用、控件与选区没有变化。

## 截图翻译不能破坏的规则

1. OCR 视觉行先合并成语义句子或段落，再一次批量翻译；不要改回逐行请求，速度会明显下降。
2. 系统快捷指令可以使用内部序号对齐，但显示前必须清理所有内部标记，不能出现 `YGUI...` 或 `[[0000]]`。
3. 只有整行都是 URL、邮箱或纯数字时才跳过翻译；包含 URL 的正常句子仍要翻译。
4. 译文横向位置和宽度必须锚定原 OCR 区域，不能跑到右侧按钮、其他列或空白位置。
5. 可以使用同列上下安全空白增加高度，但相邻句子不能重叠。
6. 译文必须完整显示，不允许省略号。字体根据句子和可用空间自适应，有空间时适量放大，极端长文本最低可到 7pt；7pt 仍不够时扩大逻辑画布，不能依赖 SwiftUI `.clipped()` 裁字。
7. 覆盖层是可激活、可成为 key window 的 `NSPanel`，显示时主动激活应用；窗口级本地 `NSEvent` monitor 接收 `.magnify`，捏合和工具栏按钮都直接调整窗口尺寸，窗口、底图和译文同步缩放，不接管双指滚动。
8. 截图窗口只停留在触发时的桌面 Space，不能跨所有桌面。
9. 工具条与翻译图片应作为父子窗口整体移动；不要让两个窗口互相反向更新坐标，否则会抖动。
10. 任何因 OCR 框过窄而产生非必要换行的文本都会保留左侧锚点，并可扩展到同一行下一个 OCR 区域之前；已经放得下的正文仍保持原始宽度。窗口缩放会以新尺寸命中布局缓存或重新运行 CoreText 排版。
11. 每个译文块同时保留独立 `coverageFrame`：先在原始 OCR 位置绘制扩张遮盖补片，再绘制可能被纵向避让的译文。遮盖补片横向扩张约一个源文字高度，并以同排相邻区域中线为边界，防止漏出首尾原文或覆盖其他列。

截图翻译相关修改至少要保持以下测试性质：界面、性质测试和基准都调用唯一生产 `layout` 入口；完整文本、横向锚点、无重叠、无省略号、字体不低于 7pt、不越出逻辑画布、无内部标记、URL 混排正常、同一句视觉换行不被错误拆分。

当前离线性能基线（synthetic-2mp，2026-07-23）：OCR p95 `33.18ms`、分组 p95 `6.32ms`、冷布局 p95 `59.49ms`、缓存布局 p95 `0.010ms`、背景采样 p95 `9.19ms`、增量内存约 `11.23MB`。布局保证增强后冷路径高于旧实现，但布局与背景合计仍低于 `80ms` 门槛；不要用缓存命中数字冒充冷布局性能。

## 普通翻译窗口不能破坏的规则

1. 翻译窗口是单实例。每次打开新窗口前必须显式关闭旧 `NSPanel`。
2. 仅把 `TranslationEditorWindowController` 引用设为 `nil` 不会关闭 `isReleasedWhenClosed = false` 的窗口。
3. 旧窗口的关闭回调不能把新窗口引用清空；当前使用 presentation ID 防止竞态。
4. 窗口记忆用户上次宽度，只根据内容自动增加高度，不随长文本自动向右扩展。
5. 用户拖动或实时调整大小时，暂停内容自适应，避免窗口抖动。
6. 长译文下面不能预留大块空白；AppKit 测量字体必须和 SwiftUI 实际显示字体一致。

## 路径、资源和隐私

- 截图默认目录使用当前用户主目录动态生成，不能写死 `/Users/yang/...`。
- `YuanGUI.Translate.shortcut` 必须随 SwiftPM resource bundle 打入 `.app`。
- SwiftPM 开发资源用 `Bundle.module`；分发版只能依赖应用包里的资源。
- 截图、OCR 和翻译缓存只保留在内存，不写入磁盘。
- AI Key 使用 `LocalSecretStore` 的仅当前用户可读文件；不要擅自改为钥匙串。
- Bilibili Cookie 和令牌只保存在当前用户的应用数据目录，不保存账号密码。
- 清理和卸载功能必须继续执行路径规范化、允许目录、符号链接、扫描后状态复核和共享数据保护。

## 手动验收交给用户的项目

完成脚本和测试后，提醒用户手动检查：

- 首次屏幕录制、辅助功能、位置和 Apple Events 权限；
- 女朋友或另一台 Mac 上的权限记录和划词兼容性；
- Safari、Chrome、Edge 以及普通可编辑应用中的划词；
- 翻译窗口是否单实例、是否抖动、长文本是否留白；
- 邮件、网页、多列、小控件、深色背景和 Retina 截图的翻译可读性；
- 工具条跟随、缩放、`Esc`、中英对照与多桌面；
- 锁定后只显示约 48×48pt 解锁按钮；播报、监控和歌词切换时角色位置不瞬移；
- 持续下雨时约 10 秒后能恢复听歌动作，紧急状态解除后恢复当前活动；
- 触控板以指针为中心捏合、窗口与译图同步缩放、原图/译图同步，以及标题横向空白利用；
- Bilibili 手动切歌后的选中状态和歌词匹配。

不要为了完成这些人工项目而自行启动 Computer Use。

## 发布时才做

只有用户明确要求发布时才执行以下流程：

1. 更新 `AppUpdateService.swift` 的 fallback version、build 和版本摘要；
2. 更新 `script/build_and_run.sh` 的版本与 build；
3. 更新 `script/package_dmg.sh` 的默认版本与 build；
4. 更新 `README.md`、`RELEASE_NOTES.md` 和下载文件名；
5. 运行全量 `swift test`；
6. 生成 DMG，校验版本、Bundle ID、签名、镜像和 SHA-256；
7. 按用户要求提交、推送、创建标签和 Release；
8. 上传后读取 GitHub Release 元数据确认资产名称与摘要。

不要随意移动已经发布的标签。只有用户明确要求覆盖同一版本时才可强制更新标签或使用 `gh release upload --clobber`，并严格遵守其对 Release notes 的要求。

## 修改完成后的汇报格式

简洁说明：

- 改了什么；
- 根因是什么；
- 跑了哪些命令和测试；
- 哪些 GUI 项目仍需用户手动验证；
- 是否提交、推送或发布。

不要把工具调用过程写成冗长流水账。

## 2026-07-27 英文本地化：状态栏工具列表遗漏

- 状态栏 Dashboard 的 “More Tools” 复用 `DashboardCompactActionLabel`。该组件的 `title` 与 `subtitle` 是普通 `String`，SwiftUI 不会自动把它们当作本地化键；因此虽然 `Localizable.strings` 已有翻译，划词翻译、清理屋、软件卸载和设置仍会在英文界面显示中文。
- 所有可复用展示组件只要接收普通 `String` 语义键，必须在组件内部使用 `AppLocalizer.string(...)` 渲染标题、副标题、帮助和可访问性标签。不要只依赖调用点的字符串字面量自动本地化。
- 修复位置：`Sources/YuanGUI/Views/Dashboard/DashboardToolsView.swift` 的 `DashboardCompactActionLabel`；标题和副标题都显式查表。
- 回归时必须在英文环境检查 Dashboard 的 Overview、Music、Tools 三页，特别是 “More Tools” 的每个紧凑行和更新行。

## 2026-07-28 英文动态格式与角色菜单回归

- `MetricFormatting.uptime`、Focus 的 Stepper 标签和日记自动备份计数以前在 Swift 中拼接中文单位；必须使用 `AppLocalizer.format` 和 `%ld` 占位符资源。动态数字、日期和应用名称不是普通 SwiftUI 本地化字面量。
- 小尺寸桌宠顶部的角色菜单需要完整显示 `YuanGUI`。不要扩大 `PetLayout.compactSideControlsWidth`：它参与底栏安全间距计算，会与工具栏重叠。应保持 48pt 的布局列宽，仅让顶部 `Menu` 标签在透明侧向空间中以 76pt 视觉宽度绘制。
- 回归要检查：运行时长（例如 `Running 5d 4h`）、Focus 时长、备份数量/每日每周计数，以及 50%/60% 缩放下顶部角色菜单和底栏不重叠。

## 2026-07-28 桌宠工具栏本地化

- `PetBottomControlsView` 的悬浮提示通过共享 `PetHoverLabel` 渲染。`PetHoverLabel` 必须对传入的普通 `String` 调用 `AppLocalizer.string`，否则五个图标按钮会在英文环境全部显示中文。
- 工具栏按钮的 `.help` 和 `.accessibilityLabel` 也必须显式查表；覆盖迷你监控、AI 对话、迷你播放器、快速记录、锁定与解锁，以及侧边角色/专注/清理/卸载控制。
- 新增 `YuanGUI 音乐播放器` 的英中资源。英文回归时逐个悬停五个底栏图标，并用 VoiceOver 检查标签。

## 2026-07-28 桌宠气泡与清理屋权限时机

- 桌宠气泡不只有 `PetStatusMessageResolver`：`PetStore.showSmartMessage` 会生成充电、低电量、内存、雨天与夜间的动态环境文案，`PetAmbientBubble`、`PetStatusBubble`、`PetEdgeMessageBubbleView`、`PetEdgeMiniStatusView` 又各自负责显示。英文文案必须在动态生成处按 `AppLocalizer.effectiveLanguage` 生成，并在所有显示组件对普通 `String` 再调用 `AppLocalizer.string(...)`，防止静态语义键漏译。
- 充电预计时长不能沿用中文拼接单位；英文使用 `PetStore.ambientDurationTextEnglish`（如 `2h 20m`）。状态卡的 CPU、Memory、Battery 标签和辅助气泡的状态标题也要显式查表。
- 不得在 `PetStore`、`MaintenanceStore`、窗口创建或桌宠展示时创建默认 `CleanupScanner`。`MaintenanceStore` 采用可选注入 scanner：测试可以传 fake/真实 scanner，生产默认 scanner 仅在用户开始 `scanCleanup()` 或 `scanApplications()` 时创建。这样 Desktop/Downloads 的旧安装包枚举只可能发生在用户主动进入清理屋并启动扫描之后。
- 同一条规则也适用于 `NativeMaintenanceService`：它的默认参数原先会构造 `SafePathValidator()`，而 validator 会对默认允许路径解析符号链接；默认路径中的 Desktop/Downloads 足以在桌宠启动时触发 TCC。`MaintenanceStore` 的 handler 现在同样可选注入、仅在用户确认清理/卸载时创建。`SafePathValidator.defaultAllowedRoots` 不再包括 Desktop/Downloads；旧安装包候选在扫描时记录自己的 `executionRoot`，执行时才以该根目录扩展验证范围。
- 不要把既有的 `DesktopIconService.areDesktopIconsVisible()` 当作清理屋权限回归的根因；它在清理屋升级前已经存在。2026-07-28 排查发现 `/Applications/YuanGUI.app` 仍是 2.6.1 (15)，而工作区 `dist/YuanGUI.app` 是 2.7.0 (16)，因此权限截图来自旧安装副本，不能用于判断当前未提交改动。验证当前修复必须明确运行 `dist/YuanGUI.app`，或在用户授权后安装该构建到 `/Applications`。
- 工作区位于 `~/Desktop/projet/YuanGUI`。从 `dist/YuanGUI.app` 直接运行时，macOS 会把应用读取自己的可执行文件和资源包也视为 Desktop 文件夹访问；这与清理屋无关，业务代码无法规避。`script/build_and_run.sh` 的 `run`、`--verify`、`--logs`、`--telemetry` 统一通过 `open_app()` 把 `dist` 包复制到 `/private/tmp/YuanGUI-run-$UID/YuanGUI.app` 后启动；`dist` 仍保留为可检查/打包制品。开发回归应使用该脚本启动，而不要在 Finder 中双击 Desktop 下的 `dist` 包。

## 2026-07-28 P1：清理屋运行时英文泄漏

- `AppLocalizer.string` 只能查静态键，绝不能在字符串插值完成后拿来翻译。动态消息必须使用语义格式键，例如 `maintenance.progress.scanningCategory`、`maintenance.result.deletedAndTrashed`、`maintenance.error.protectedPath`，再以 `AppLocalizer.format(key, arguments...)` 传参。
- 清理屋的文本来源横跨 `MaintenanceStore`（扫描和执行状态）、`CleanupService`（进度、候选原因、卸载警告、跳过和错误）、`SafePathError`、`MaintenanceModels` 以及退出/更新时的日记保存失败。所有面向用户的运行时文本已改用 `maintenance.*` 或 `diary.error.*` 键；不要重新引入直接拼接的中文反馈。
- `LocalizationTests.testMaintenanceRuntimeKeysExistInBothLanguages` 覆盖关键格式键及英文格式结果；与现有英中键集一致性、英文值无中文测试一同作为回归保护。
- README 英文入口应与中文 README 信息结构对齐。保留中文界面标签、图标和角色视觉说明；尚未提供的 GIF 以明确 HTML 注释占位，不要伪造媒体链接。两份 README 顶部使用 `English | 简体中文` 式语言选择栏。

## 2026-07-28 清理屋权限边界

- 打开清理屋只展示 `maintenance.welcome` 安全说明与“开始扫描”操作；不要在 `MaintenanceView.onAppear`、窗口创建或路由时扫描。只有用户点击开始扫描（或明确点击桌宠的清理快捷操作）才调用 `MaintenanceStore.scanCleanup()`。
- `CleanupScanConfiguration.defaultEnabledCategories` 只包含 `.appCache`、`.oldLog`、`.crashReport`。浏览器缓存、开发工具缓存、项目构建产物、旧安装包和孤儿残留首次运行全部关闭；已有用户保存的显式设置保持不变。
- 启用 `.oldInstallerPackage` 时，`MaintenanceView` 必须先显示 `maintenance.installerPermission` 提示：该规则会在下一次扫描时检查 Downloads/Desktop 内的旧 DMG、PKG 等文件，macOS 可能请求权限。确认前不要把分类写入设置或启动任何扫描。
- `MaintenanceTests.testDefaultCleanupConfigurationExcludesReviewCategories` 是默认范围的回归测试。

## 2026-07-28 英文紧凑窗口布局

- 清理屋实际最小宽度为 760pt；英文按钮与菜单不能强制全部塞进同一行。`MaintenanceView.cleanupToolbar` 以 940pt 为断点：宽窗口提供搜索、排序和直接操作；窄窗口改为“扫描 + Options 菜单 + 已选大小 + 开始清理”，避免省略号。不要为了显示英文而盲目扩大窗口最小宽度。
- 所有动态数量与确认框使用 `maintenance.ui.*`、`maintenance.confirm.*` 格式键，不能拼接中文“项/个组件/已选”。AppKit `NSAlert` 不会自动本地化 Swift 字面量，必须显式 `AppLocalizer.string/format`。
- 回归：英文环境下触发充电、低电量、内存压力、贴边消息与环境气泡；新开桌宠不应出现文件夹访问请求，点击清理屋的“扫描可清理空间”后才允许系统按扫描范围请求权限。

## 2026-07-28 音乐播放器英文布局

- `MusicWindowController` 的 AppKit 窗口标题也属于展示层，必须通过 `AppLocalizer.string("YuanGUI 音乐播放器")` 获取，不能写死 “YuanGUI 音乐”。
- 英文的歌词控制不可把字号标签、滑块、字体选择、颜色选择与“Lock and Allow Click-through”开关塞进同一个 `HStack`。`MusicPlayerViews.lyricsAdjustments` 应保持“偏移”“字号”“字体与颜色”“锁定”四段纵向布局；长英文开关独占一行。此规则在 760pt 最小窗口以及分栏后的窄详情区都适用。
- 新用户在英文模式下，桌面歌词默认使用 macOS System Font；简体中文仍默认 Rounded。已有 `musicLyricsFontStyle` 设置永远优先，不因语言切换被覆盖。中文字体依旧是用户可选项。

## 2026-07-28 音乐播放器英文布局

- `MusicWindowController` 的 AppKit 窗口标题也属于展示层，必须通过 `AppLocalizer.string("YuanGUI 音乐播放器")` 获取，不能写死 “YuanGUI 音乐”。
- 英文的歌词控制不可把字号标签、滑块、字体选择、颜色选择与“Lock and Allow Click-through”开关塞进同一个 `HStack`。`MusicPlayerViews.lyricsAdjustments` 应保持“偏移”“字号”“字体与颜色”“锁定”四段纵向布局；长英文开关独占一行。此规则在 760pt 最小窗口以及分栏后的窄详情区都适用。

## 2026-07-26 桌宠贴边优化交接

本轮目标是“磁吸 + 半探头 + 平滑切换”。贴边实现已经拆成以下边界：

- `Sources/YuanGUI/Support/PetLayout.swift`：`dockPreviewThreshold = 56`，`dockCommitThreshold = 28`；`dockingCandidate` 使用角色素材的 `normalizedVisibleBounds` 对应的真实可见矩形，不再使用视觉矩形中心越界判断。新拖拽默认只启用 `defaultDockEdges = [.left, .right]`，顶部和底部的纯布局函数仍保留以兼容旧数据和测试。
- `Sources/YuanGUI/Support/PetPanel.swift`：拖拽中只发布 `PetPanel.dockCandidate` 和边缘预览光带，不强行修改窗口位置；松手且候选进入 28pt 提交区才吸附。贴边和恢复使用主窗口与边缘窗口交叉淡入，主动画约 0.24-0.30 秒。
- `Sources/YuanGUI/Views/PetRootView.swift`：候选区视觉反馈为轻微缩放、透明度和朝边缘倾斜，遵守 Reduce Motion。
- `Sources/YuanGUI/Views/PetEdgePeekView.swift`：圆形按钮改为出屏的角色探头。静止露出约 40pt，悬停后窗口向内滑到约 62pt；监控卡片悬停 300ms 后展开，离开 500ms 后收回，紧急状态可直接展示。
- `Sources/YuanGUI/Support/SpriteLoader.swift`：专用探头素材优先从 `Resources/Sprites/EdgePeek/` 加载，缺失时回退角色当前动作图。

专用素材槽位已保留，后续只替换以下文件即可：

- `Sources/YuanGUI/Resources/Sprites/EdgePeek/yuangui_edge_left.png`
- `Sources/YuanGUI/Resources/Sprites/EdgePeek/yuangui_edge_right.png`
- `Sources/YuanGUI/Resources/Sprites/EdgePeek/vcc_edge_left.png`
- `Sources/YuanGUI/Resources/Sprites/EdgePeek/vcc_edge_right.png`
- `Sources/YuanGUI/Resources/Sprites/EdgePeek/duo_edge_left.png`
- `Sources/YuanGUI/Resources/Sprites/EdgePeek/duo_edge_right.png`

六个 PNG 尚未生成。当前会话没有暴露内置 `image_gen` 调用入口；按照 imagegen 技能约束，没有静默切换到需要 `OPENAI_API_KEY` 的 CLI 降级路径。素材生成后应使用 512x512、带 alpha 的 PNG，角色只保留脑袋/上半身和扒边双手，不要文字、背景、阴影或圆形按钮。`PetMode.duo` 使用 `duo_edge_left/right`，缺失时继续回退当前动作图。

验证状态：主程序目标和应用包均已成功编译；`swift test` 执行 285 项，2 项网络测试按项目默认跳过，0 失败；`./script/build_and_run.sh --verify` 已成功启动 `dist/YuanGUI.app`。第一次测试曾因沙箱无法写入 Xcode/Clang 用户缓存失败，授权后已恢复正常。人工验收重点是拖拽靠近左右边缘的 56/28 两级反馈、探头在屏幕外的露出宽度、悬停状态卡延迟和贴边/恢复时是否闪烁。

## 2026-07-28 本地音乐

- 实现位于 `codex/local-music`：新增 `.local` 来源、通用 `URLMusicPlayerEngine`、`MusicPlaybackQueue`、`LocalMusicImportService`、安全作用域书签、元数据/封面缓存、同名 LRC 优先级、完整播放器与菜单栏入口。
- 只允许在用户点击导入后读取其选择的文件或文件夹；支持 MP3、M4A、AAC、WAV、AIFF，FLAC 暂未启用。不得在启动或打开音乐页时扫描 Desktop、Downloads、Documents、Music 或主目录。
- 全量 `swift test` 为 310 项、2 项网络测试跳过、0 失败，`./script/build_and_run.sh --verify` 成功。

## 2026-07-29 2.7.0 发布与更新说明

- `v2.7.0` 已发布，Release 正文使用英文版 2.7.0 章节；`RELEASE_NOTES.md` 与 `RELEASE_NOTES.zh-CN.md` 作为两个独立 Release 资产上传，DMG 资产仍为 `YuanGUI-2.7.0.dmg`。
- `AppUpdateService` 从 GitHub Release 资产按当前有效语言选择更新说明：中文读取 `RELEASE_NOTES.zh-CN.md`，英文/系统英文读取 `RELEASE_NOTES.md`；缺少 Markdown 资产的旧 Release 回退 API `body`。`AboutUpdateView` 展示下载后的 Markdown。
- Release 文件必须保持中英文内容独立，不要再把两份文件拼成同一个正文。GitHub 同一 tag 只有一个正文栏，因此语言文件应作为独立资产保留。

## 2026-07-29 清理台 UI 重构

- `Sources/YuanGUI/Views/MaintenanceDesign.swift` 提供清理台统一设计常量、状态头部、页签和命令卡；macOS 26 使用 `GlassEffectContainer`/`glassEffect`，macOS 15–25 通过 `YuanLiquidGlass` 降级为系统 Material/边框按钮。
- `MaintenanceView` 不再使用 `GeometryReader` 强行把搜索、排序、白名单、扫描范围和操作按钮塞进一行；清理和卸载均采用两行命令卡，避免英文长文本省略。
- 空状态、候选列表、卸载列表和操作记录使用单层玻璃内容卡；候选原因、应用警告和文件路径允许最多两行，路径使用中间截断，动态消息保留两行并遵守 Reduce Motion。
- 清理台仍然只在用户主动扫描/确认后创建扫描器和执行服务，不得在窗口展示时触碰 Desktop、Downloads 等受保护目录。

## 2026-07-29 清理台选中页签对比度

- `MaintenanceTabButton` 的选中玻璃必须把标签绘制在玻璃背景之上，使用明确的 accent 前景、半透明 accent tint 和细描边；不要只使用低对比度 `.primary` 叠在浅色玻璃上，否则 macOS 26 的 vibrancy 会让英文/中文页签都变得模糊。
- 清理台的页签、命令卡、空状态和列表继续保持单层 Liquid Glass；页签高度由 `MaintenanceDesign.tabHeight` 统一，避免匹配动画或弹性布局拉伸选中背景。
- 视觉层级参考状态栏的原生玻璃控制和手帐本的 `diarySelection`/卡片间距：主操作使用系统强调玻璃，页面分组使用轻量表面和清晰的选中态，不用大块不透明灰色底板。

## 2026-07-29 桌宠迷你清理屋定位与截断

- 迷你清理/卸载卡片由 `PetAuxiliaryBubblePanel` 承载，和歌词、状态气泡共用跟随桌宠的定位；不要再把它作为 `PetRootView` 内容塞进主 `PetPanel`，否则 quick mode 会改变主窗口尺寸并造成桌宠跳动或越出屏幕。
- `PetAuxiliaryBubbleView` 的优先级为迷你清理屋、歌词、环境/状态对白；清理卡尺寸由 `PetLayout.auxiliaryBubblePanelSize(scale:showsMaintenance:)` 提供，当前固定为 360pt 宽、紧凑高度。气泡位置继续使用 `auxiliaryBubbleLayout`，靠近屏幕上边缘时自动翻到桌宠下方。
- 迷你清理屋展示摘要、可滚动的完整候选列表和单一主操作，不要用 `prefix(4)` 永远截断后续项目；长文件名/应用名最多两行，完整检索和排序交给正式清理屋窗口。按钮和摘要必须使用 `maintenance.quick.*` 双语资源，不能用插值后的中文字符串。

## 2026-07-29 CI 缓存

- `.github/workflows/tests.yml` 使用 `actions/cache@v5` 缓存 `.build`，缓存键包含 runner、架构、Swift 工具链、`Package.swift`/`Package.resolved` 哈希和提交 SHA；恢复键按依赖和工具链逐级回退。

## 2026-07-29 番茄钟与迷你清理屋可读性

- `FocusTimerStore.statusTitle` 必须通过 `AppLocalizer` 读取，不能把动态状态直接保留为中文源文本；番茄钟控制卡的时长、说明和按钮也要用本地化键。说明文字允许最多两行，Toast 同样必须换行，避免英文界面出现“英文标题 + 中文状态”或被省略号截断。
- `FocusTimerControlView` 使用宽度约 148pt 的紧凑玻璃卡：顶部仅保留 timer 图标和“专注”，中间直接显示大号等宽时间，不再恢复大圆环；空闲和完成态下方用减 5 分钟/当前时长/加 5 分钟，底部只显示状态对应的图标按钮。开始按钮可使用整行强调样式，但不能让英文或中文变成省略号。
- 倒计时数字使用 `.monospacedDigit()` 与 `.contentTransition(.numericText())`，状态切换使用轻量动画；主按钮使用红橙渐变和 hover/press 反馈，次按钮保持轻玻璃。图标按钮要有本地化辅助功能标签。
- AI 流式回复由 `ChatStore` 以 50ms 节流合并 partial reply，再刷新 `latestReply`；服务层仍可逐 token 读取，但不能逐 token 触发 SwiftUI 更新。
- `PetRootView` 的根视图不能对 `chat.isPresented` 做隐式动画；窗口 frame 使用 `.animation(nil, value: panelSize)`，聊天层单独使用 0.14 秒 opacity + 0.97 scale 淡出，控制按钮层单独动画。关闭聊天后等待聊天卡淡出约 150ms，再调用 `pet.setChatting(false)`，避免桌宠图片和窗口状态同帧二次刷新。
- `yuanPetBubbleGlass` 支持 `.regular`/`.clear` 两种表面。迷你清理/卸载卡必须使用 `.regular`，避免桌面壁纸或窗口背景穿透后影响候选项和操作按钮的可读性；歌词、普通状态对白可继续使用 clear 玻璃。
- 桌宠侧栏继续保留快速清理和卸载入口；迷你清理/卸载卡底部原来的 `More` 按钮改为直接打开完整清理屋（按当前页签进入清理或卸载页），不再套一层菜单。扫描进行中主桌宠面板保持原有紧凑尺寸，扫描卡在独立辅助面板中贴近桌宠底部/屏幕边界定位，不能通过扩大主面板把桌宠推离底部。
- 扫描/执行阶段的辅助卡只需要标题、进度和关闭操作，使用 `PetLayout.maintenanceScanningHeight`；只有扫描完成并显示候选列表时才使用 `maintenanceHeight`。`PetPanel` 必须监听 `isScanning`/`isWorking` 的边界变化并同步调整辅助面板尺寸，否则卡片会按结果态高度居中，导致桌宠与扫描卡之间出现巨大空隙。
- 操作完成后只显示完成摘要和后续操作，使用 `PetLayout.maintenanceCompletionHeight`，不能继续占用候选结果列表的高度。
- 迷你清理卡只允许风险为 `recommended` 的项目直接执行；`review` 必须禁用选择、显示“需检查”风险徽章并引导打开完整清理屋，`protected` 始终禁用。`MaintenanceStore.cleanSelected()` 和卸载快速路径也必须在模型层再次过滤，不能只依赖 View 的 disabled 状态。
- 卸载迷你卡展开应用时必须遍历全部 `application.components`，不能再使用 `prefix(3)` 隐藏后续组件；滚动区域负责承载长列表。
- `MaintenanceView` 的完整清理屋所有菜单、按钮、空状态、活动记录摘要和动态“移除/结果”文本都必须通过 `AppLocalizer` 或双语格式化键渲染；英文模式不能残留中文源文本。应用内 2.7.0 更新摘要由 `AppVersionInfo.currentReleaseHighlights` 读取 `release.2.7.*` 双语键，新增条目必须同步维护 `RELEASE_NOTES.md`、`RELEASE_NOTES.zh-CN.md` 和两套本地化资源。

## 2026-07-30 AI 聊天展示状态机、流式发布与番茄钟动态效果

- AI 聊天的逻辑开关仍由 `ChatStore.isPresented` 表示，但窗口和聊天内容的视觉生命周期统一由 `ChatPresentationCoordinator` 管理，阶段为 `hidden`、`presenting`、`presented`、`dismissing`。`PetRootView` 和 `WindowCoordinator` 不得再各自维护延迟关闭任务。
- 聊天打开时先恢复停靠、记录紧凑原点并由 AppKit 原子扩大 `PetPanel`，再切换聊天桌宠动作、显示聊天层和聚焦输入框。关闭时面板在约 0.14 秒 opacity + 0.97 scale 内容动画期间保持聊天尺寸；动画结束后移除聊天层、原子恢复紧凑尺寸与原点，再 `Task.yield()` 后执行 `pet.setChatting(false)`。
- 所有聊天展示延迟必须可取消，并同时校验 generation 与当前 phase。关闭期间重新打开必须取消旧任务，旧任务不得再移除新聊天、收缩窗口或清除聊天动作。Reduce Motion 路径跳过正常动画等待。
- `PetRootView` 的根 frame、角色底部 inset、侧边控制和辅助气泡抑制都依据视觉展示阶段，不直接跟随逻辑 `chat.isPresented` 瞬间收缩；根视图继续禁止针对面板尺寸的隐式动画，AppKit 仍是窗口 frame 的唯一控制方。
- `ChatStore` 将生成中的最新 partial 保存在非 Published 缓冲。聊天可见时最多每 50ms 发布一次 `latestReply`；隐藏时取消节流任务但保留最新缓冲，不再高频发布。重新打开时立即发布当前会话的 pending partial，否则从当前会话恢复最终 assistant 回复。
- 最终回复到达时先取消 pending partial，只向目标会话追加一个完整 assistant message；隐藏时不为气泡额外发布 `latestReply`。切换、新建、删除、清空会话或发送失败时必须清理不再适用的 pending，旧会话的 partial、最终回复和错误都不得进入新会话。
- `FocusTimerControlView` 的空闲/完成态只显示一次主要时长，减 5 分钟和加 5 分钟按钮不再夹带重复时长。Reduce Motion 开启时禁用状态切换动画、完成 bounce、hover/press scale；允许保留 hover 颜色和轻微按压 opacity，数字仍正常更新。
- `PetRootView` 顶部短暂 toast 使用 `PetToastView`：短文本按固有宽度显示，不能接受根面板宽度提案后拉成整条；长文本才在面板允许的最大宽度内换行。

## 2026-07-30 音乐订阅隔离与门面架构

- `MusicFeature` 是非 Observable 的兼容门面和组合入口，不能重新加入 `ObservableObject`、`@Published` 或聚合 `objectWillChange`。播放、资料库、歌词、歌词呈现、Bilibili 账号/导入和本地导入继续由独立 Store 发布。
- `ObservedMusicFeature` 已删除。SwiftUI 视图必须以普通 `let music` 发送命令，并只用 `@ObservedObject` 订阅自己读取的子 Store；只显示进度的视图直接观察 `MusicPlaybackProgress`。禁止为了少写初始化代码重新建立同时观察全部音乐 Store 的包装器。
- 完整播放器的 Bilibili 导入、账号、本地导入和错误呈现必须保持为各自的观察叶节点，不能把这些 Store 提升回 `MusicPlayerView` 外壳；收藏夹导入进度不得重算播放器外壳或 `MusicProgressView`。
- 已删除聚合全部业务的 `MusicFeatureRuntime`、`MusicFeatureContext` 和向子类暴露全部领域状态的 `MusicDomainCoordinator`。`MusicFeature` 直接组合七个 Store 与五个领域协作者，跨域流程只在门面中编排；禁止重新引入服务定位器、全域基类、Runtime、Manager extension 或转发壳。
- Coordinator 只能持有自己的 Store、服务和任务，并通过 MainActor 窄协议访问必要能力：播放与歌词通过 delegate 请求门面编排，资料库只依赖 `MusicLibraryPlaybackAccess`、`MusicLibraryLyricsAccess` 和 `MusicLibraryArtworkAccess`，Bilibili 与本地音乐不能获取具体兄弟 Coordinator。
- 播放器实例、Apple Music 同步、来源切换和播放队列由 `MusicPlaybackCoordinator` 持有；歌词任务与缓存由 `MusicLyricsCoordinator` 持有；账号/收藏夹任务和本地导入/封面维护任务分别由 Bilibili、本地音乐协调器持有。Facade 可以协调曲目切换、队列重建、歌词刷新与持久化，但业务实现不能回流到门面。
- 播放、资料库、歌词、Bilibili 和本地音乐命令通过 MainActor 领域协议暴露；持久化 revision、恢复时的版本校验、延迟保存和 shutdown flush 由 `MusicPersistenceCoordinator` 负责。所有服务接口和 `MusicLibrarySnapshot` 格式保持兼容。
- 所有非结构化异步操作必须有 Coordinator 所有的任务句柄或进入 `MusicTaskRegistry`；同 key 被替换的旧任务也必须保留到真正结束。shutdown 先设置关闭状态并推进 generation，再 cancel 和 await 全部任务；每个 await 后的 UI、资料库和持久化提交都要校验 cancellation、generation 或等价 revision，不能依赖服务正确响应 cancellation。
- `MusicFeature.shutdown()` 按依赖方向关闭：先停止可能向兄弟域提交结果的 Bilibili 与本地音乐，再停止播放、歌词，最后由资料库完成 persistence flush；不能先释放/关闭下游再等待上游任务。
- 音乐性能回归以 publisher 隔离、挂起服务后的 shutdown 生命周期测试和 SwiftUI Instruments 的 View Body Updates 验收：播放进度不得使资料库、设置或桌宠根视图刷新；账号、资料库和导入进度不得使播放进度与传输控制刷新。测试必须验证实际状态/发布结果，不能用文件行数、类型名称或任务变量字符串代替行为验证。
