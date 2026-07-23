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
    private let runtime = AppRuntime()

    func applicationDidFinishLaunching(_ notification: Notification) {
        runtime.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        runtime.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        runtime.applicationShouldTerminate(sender)
    }
}

@MainActor
final class AppRuntime {
    let pet = PetStore()
    let aiSettings = AISettingsStore()
    let loginItem = LoginItemStore()
    lazy var focusTimer = FocusTimerStore(pet: pet)
    lazy var chat = ChatStore(settings: aiSettings)
    lazy var maintenance = MaintenanceStore(pet: pet)
    lazy var music = MusicFeature()
    lazy var quickTools = QuickToolsController(aiSettings: aiSettings)
    private lazy var windows = WindowCoordinator(
        pet: pet,
        aiSettings: aiSettings,
        loginItem: loginItem,
        focusTimer: focusTimer,
        chat: chat,
        maintenance: maintenance,
        music: music,
        quickTools: quickTools,
        terminateForUpdate: { [weak self] in self?.prepareToTerminateForUpdate() }
    )
    private var terminationTask: Task<Void, Never>?
    private var isPreparingUpdateTermination = false
    private var isUpdateTerminationReady = false

    func start() {
        NSApp.setActivationPolicy(.accessory)
        windows.start()
    }

    func stop() {
        windows.stop()
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
            await music.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func prepareToTerminateForUpdate() {
        guard !isPreparingUpdateTermination, !isUpdateTerminationReady else { return }
        isPreparingUpdateTermination = true
        terminationTask = Task { [weak self] in
            guard let self else {
                NSApp.terminate(nil)
                return
            }
            await music.shutdown()
            isUpdateTerminationReady = true
            isPreparingUpdateTermination = false
            NSApp.terminate(nil)
        }
    }
}

@MainActor
final class WindowCoordinator: NSObject {
    private let pet: PetStore
    private let aiSettings: AISettingsStore
    private let loginItem: LoginItemStore
    private let focusTimer: FocusTimerStore
    private let chat: ChatStore
    private let maintenance: MaintenanceStore
    private let music: MusicFeature
    private let quickTools: QuickToolsController
    private let terminateForUpdate: () -> Void
    private var panelController: PetPanelController?
    private var statusItem: NSStatusItem?
    private var dashboardController: StatusDashboardPanelController?
    private var settingsController: SettingsWindowController?
    private var chatHistoryController: ChatHistoryWindowController?
    private var maintenanceController: MaintenanceWindowController?
    private var musicController: MusicWindowController?
    private var lyricsController: LyricsPanelController?
    private var weatherStartupTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    private lazy var actions = AppActions(
        open: { [weak self] route in self?.open(route) },
        runQuickTool: { [weak self] route in self?.runQuickTool(route) },
        terminateForUpdate: { [weak self] in self?.terminateForUpdate() }
    )

    init(
        pet: PetStore,
        aiSettings: AISettingsStore,
        loginItem: LoginItemStore,
        focusTimer: FocusTimerStore,
        chat: ChatStore,
        maintenance: MaintenanceStore,
        music: MusicFeature,
        quickTools: QuickToolsController,
        terminateForUpdate: @escaping () -> Void
    ) {
        self.pet = pet
        self.aiSettings = aiSettings
        self.loginItem = loginItem
        self.focusTimer = focusTimer
        self.chat = chat
        self.maintenance = maintenance
        self.music = music
        self.quickTools = quickTools
        self.terminateForUpdate = terminateForUpdate
    }

    func start() {
        installMainMenu()
        quickTools.start()
        panelController = PetPanelController(
            store: pet,
            chat: chat,
            maintenance: maintenance,
            focusTimer: focusTimer,
            music: music,
            appActions: actions
        )
        panelController?.show()
        installMenuBarItem()
        lyrics().updateVisibility()
        music.lyricsPresentation.onVisibilityChanged = { [weak self] in self?.lyrics().updateVisibility() }
        music.lyricsPresentation.onLockChanged = { [weak self] in self?.lyrics().updateLock() }
        weatherStartupTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.pet.weather.start()
        }
        chat.$isPresented
            .removeDuplicates()
            .sink { [weak self] presented in
                Task { @MainActor [weak self] in
                    guard let self, self.chat.isPresented == presented else { return }
                    self.pet.setChatting(presented)
                    if presented { self.panelController?.focusForChatInput() }
                }
            }
            .store(in: &cancellables)
    }

    func stop() {
        weatherStartupTask?.cancel()
        pet.monitor.stop()
        quickTools.stop()
        music.lyricsPresentation.onVisibilityChanged = nil
        music.lyricsPresentation.onLockChanged = nil
    }

    func open(_ route: AppRoute) {
        switch route {
        case .statusDashboard:
            guard let button = statusItem?.button else { return }
            dashboard().show(relativeTo: button)
        case .chat:
            chat.togglePresented()
        case .settings(let tab):
            showSettings(tab: tab)
        case .chatHistory:
            showChatHistory()
        case .maintenance(let tab):
            maintenance.selectTab(tab)
            showMaintenance()
        case .music:
            dashboardController?.hide()
            DispatchQueue.main.async { [weak self] in self?.showMusic() }
        }
    }

    private func runQuickTool(_ route: QuickToolRoute) {
        switch route {
        case .regionScreenshot: quickTools.beginRegionScreenshot()
        case .screenshotTranslation: quickTools.beginScreenshotTranslation()
        case .translateSelection: quickTools.translateSelection()
        }
    }

    private func installMainMenu() {
        let mainMenu = NSMenu(title: "主菜单")
        let applicationItem = NSMenuItem(title: "YuanGUI", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "YuanGUI")
        applicationMenu.addItem(
            withTitle: "退出 YuanGUI",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
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
        for item in toolsMenu.items { item.target = self }
        toolsItem.submenu = toolsMenu
        mainMenu.addItem(toolsItem)
        NSApp.mainMenu = mainMenu
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
        self.statusItem = statusItem
    }

    @objc private func toggleDashboard() {
        guard let button = statusItem?.button else { return }
        dashboard().toggle(relativeTo: button)
    }

    private func dashboard() -> StatusDashboardPanelController {
        if let dashboardController { return dashboardController }
        let controller = StatusDashboardPanelController(
            store: pet,
            focusTimer: focusTimer,
            music: music,
            quickTools: quickTools,
            togglePet: { [weak self] in self?.panelController?.toggle() },
            showPet: { [weak self] in self?.panelController?.show() },
            openSettings: { [weak self] in self?.open(.settings(.pet)) },
            appActions: actions
        )
        dashboardController = controller
        return controller
    }

    private func showSettings(tab: SettingsTab) {
        if settingsController == nil {
            settingsController = SettingsWindowController(
                petStore: pet,
                aiSettings: aiSettings,
                loginItem: loginItem,
                focusTimer: focusTimer,
                music: music,
                quickTools: quickTools,
                showPet: { [weak self] in self?.panelController?.show() },
                appActions: actions
            )
        }
        settingsController?.show(tab: tab)
    }

    private func showChatHistory() {
        if chatHistoryController == nil {
            chatHistoryController = ChatHistoryWindowController(chat: chat)
        }
        chatHistoryController?.show()
    }

    private func showMaintenance() {
        if maintenanceController == nil {
            maintenanceController = MaintenanceWindowController(store: maintenance)
        }
        maintenanceController?.show()
    }

    private func showMusic() {
        if musicController == nil {
            musicController = MusicWindowController(music: music, appActions: actions)
        }
        musicController?.show()
    }

    private func lyrics() -> LyricsPanelController {
        if let lyricsController { return lyricsController }
        let controller = LyricsPanelController(music: music)
        lyricsController = controller
        return controller
    }

    @objc private func startRegionScreenshot() {
        runQuickTool(.regionScreenshot)
    }

    @objc private func translateSelection() {
        runQuickTool(.translateSelection)
    }

    @objc private func startScreenshotTranslation() {
        runQuickTool(.screenshotTranslation)
    }
}
