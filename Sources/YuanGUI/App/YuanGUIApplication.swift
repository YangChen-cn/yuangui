import AppKit
import Combine
import SwiftUI

@main
enum YuanGUIApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = PetStore()
    private let aiSettings = AISettingsStore()
    private let loginItemStore = LoginItemStore()
    private lazy var focusTimer = FocusTimerStore(pet: store)
    private lazy var chatStore = ChatStore(settings: aiSettings)
    private lazy var maintenanceStore = MaintenanceStore(pet: store)
    private lazy var musicStore = MusicStore()
    private lazy var quickTools = QuickToolsController(aiSettings: aiSettings)
    private var panelController: PetPanelController?
    private var statusItem: NSStatusItem?
    private var dashboardController: StatusDashboardPanelController?
    private var settingsController: SettingsWindowController?
    private var chatHistoryController: ChatHistoryWindowController?
    private var maintenanceController: MaintenanceWindowController?
    private var musicController: MusicWindowController?
    private var lyricsController: LyricsPanelController?
    private var weatherStartupTask: Task<Void, Never>?
    private var terminationTask: Task<Void, Never>?
    private var isPreparingUpdateTermination = false
    private var isUpdateTerminationReady = false
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        quickTools.start()
        panelController = PetPanelController(store: store, chat: chatStore, maintenance: maintenanceStore, focusTimer: focusTimer, music: musicStore)
        panelController?.show()
        lyrics().updateVisibility()
        installMenuBarItem()
        weatherStartupTask = Task { [weak self] in
            // Give the pet panel and menu bar item a chance to render before
            // Core Location presents its first-run permission dialog.
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.store.weather.start()
        }
        chatStore.$isPresented
            .removeDuplicates()
            .sink { [weak self] presented in
                self?.store.setChatting(presented)
                if presented { self?.panelController?.focusForChatInput() }
            }
            .store(in: &cancellables)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu(title: "主菜单")

        let applicationItem = NSMenuItem(title: "YuanGUI", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "YuanGUI")
        applicationMenu.addItem(withTitle: "退出 YuanGUI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: #selector(UndoManager.undo), keyEquivalent: "z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let toolsItem = NSMenuItem(title: "工具", action: nil, keyEquivalent: "")
        let toolsMenu = NSMenu(title: "工具")
        toolsMenu.addItem(withTitle: "区域截图", action: #selector(startRegionScreenshot), keyEquivalent: "")
        toolsMenu.addItem(withTitle: "截图翻译", action: #selector(startScreenshotTranslation), keyEquivalent: "")
        toolsMenu.addItem(withTitle: "翻译所选文字", action: #selector(translateSelection), keyEquivalent: "")
        toolsItem.submenu = toolsMenu
        mainMenu.addItem(toolsItem)

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        weatherStartupTask?.cancel()
        store.monitor.stop()
        quickTools.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isUpdateTerminationReady { return .terminateNow }
        if isPreparingUpdateTermination { return .terminateLater }
        guard terminationTask == nil else { return .terminateLater }
        terminationTask = Task { [weak self] in
            guard let self else {
                sender.reply(toApplicationShouldTerminate: true)
                return
            }
            await musicStore.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func installMenuBarItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "pawprint.fill",
            accessibilityDescription: "元圭与 VCC"
        )

        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleDashboard)
        statusItem.button?.sendAction(on: [.leftMouseUp])

        NotificationCenter.default.publisher(for: .showYuanGUIDashboard)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, let button = self.statusItem?.button else { return }
                    self.dashboard().show(relativeTo: button)
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .showYuanGUIChat)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.chatStore.togglePresented()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .showYuanGUISettings)
            .sink { [weak self] _ in
                Task { @MainActor in self?.showSettings() }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .showYuanGUIChatHistory)
            .sink { [weak self] _ in
                Task { @MainActor in self?.showChatHistory() }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .showYuanGUIMaintenance)
            .sink { [weak self] notification in
                Task { @MainActor in
                    self?.maintenanceStore.selectTab(notification.userInfo?["tab"] as? Int ?? 0)
                    self?.showMaintenance()
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .showYuanGUIMusic)
            .sink { [weak self] _ in Task { @MainActor in self?.showMusic() } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .musicLyricsVisibilityChanged)
            .sink { [weak self] _ in Task { @MainActor in self?.lyrics().updateVisibility() } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .musicLyricsLockChanged)
            .sink { [weak self] _ in Task { @MainActor in self?.lyrics().updateLock() } }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .terminateYuanGUIForUpdate)
            .sink { [weak self] _ in
                Task { @MainActor in self?.prepareToTerminateForUpdate() }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .startYuanGUIRegionScreenshot)
            .sink { [weak self] _ in
                Task { @MainActor in self?.quickTools.beginRegionScreenshot() }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .translateYuanGUISelection)
            .sink { [weak self] _ in
                Task { @MainActor in self?.quickTools.translateSelection() }
            }
            .store(in: &cancellables)
        self.statusItem = statusItem
    }

    private func prepareToTerminateForUpdate() {
        guard !isPreparingUpdateTermination, !isUpdateTerminationReady else { return }
        isPreparingUpdateTermination = true
        terminationTask = Task { [weak self] in
            guard let self else {
                NSApp.terminate(nil)
                return
            }
            await musicStore.shutdown()
            isUpdateTerminationReady = true
            isPreparingUpdateTermination = false
            NSApp.terminate(nil)
        }
    }

    @objc private func toggleDashboard() {
        guard let button = statusItem?.button else { return }
        dashboard().toggle(relativeTo: button)
    }

    private func dashboard() -> StatusDashboardPanelController {
        if let dashboardController { return dashboardController }
        let controller = StatusDashboardPanelController(
            store: store,
            focusTimer: focusTimer,
            music: musicStore,
            quickTools: quickTools,
            togglePet: { [weak self] in self?.panelController?.toggle() },
            showPet: { [weak self] in self?.panelController?.show() },
            openSettings: { [weak self] in self?.showSettings() }
        )
        dashboardController = controller
        return controller
    }

    private func showSettings() {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                petStore: store,
                aiSettings: aiSettings,
                loginItem: loginItemStore,
                focusTimer: focusTimer,
                music: musicStore,
                quickTools: quickTools,
                showPet: { [weak self] in self?.panelController?.show() }
            )
        }
        settingsController?.show()
    }

    private func showChatHistory() {
        if chatHistoryController == nil {
            chatHistoryController = ChatHistoryWindowController(chat: chatStore)
        }
        chatHistoryController?.show()
    }

    private func showMaintenance() {
        if maintenanceController == nil {
            maintenanceController = MaintenanceWindowController(store: maintenanceStore)
        }
        maintenanceController?.show()
    }

    private func showMusic() {
        dashboardController?.hide()
        musicStore.isMiniPlayerPresented = false
        if musicController == nil { musicController = MusicWindowController(music: musicStore) }
        musicController?.show()
    }

    private func lyrics() -> LyricsPanelController {
        if let lyricsController { return lyricsController }
        let controller = LyricsPanelController(music: musicStore)
        lyricsController = controller
        return controller
    }

    @objc private func startRegionScreenshot() {
        quickTools.beginRegionScreenshot()
    }

    @objc private func translateSelection() {
        quickTools.translateSelection()
    }

    @objc private func startScreenshotTranslation() {
        quickTools.beginScreenshotTranslation()
    }

}
