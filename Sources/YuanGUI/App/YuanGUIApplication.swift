import AppKit
import SwiftUI

@main
enum YuanGUIApplication {
    @MainActor
    static func main() {
        AppLocalizer.bootstrap()
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
    private let windowActivator = ApplicationWindowActivator()
    let language = AppLanguageSettings()
    let pet = PetStore()
    let aiSettings = AISettingsStore()
    let loginItem = LoginItemStore()
    let updateService = AppUpdateService()
    lazy var focusTimer = FocusTimerStore(pet: pet)
    lazy var chat = ChatStore(settings: aiSettings)
    lazy var maintenance = MaintenanceStore(pet: pet)
    lazy var music = MusicFeature()
    lazy var diary = DiaryFeature(
        weatherService: pet.weather,
        musicFeature: music
    )
    lazy var externalAudioInterruption = ExternalAudioInterruptionController(music: music)
    lazy var petTranslationCoordinator = PetTranslationCoordinator(pet: pet)
    lazy var quickTools = QuickToolsController(
        aiSettings: aiSettings,
        petTranslationEvents: petTranslationCoordinator,
        windowActivator: windowActivator
    )
    lazy var updateStore: AppUpdateStore = {
        let store = AppUpdateStore(service: updateService)
        store.setTerminationHandler { [weak self] in
            guard let self else { return false }
            return await self.prepareToTerminateForUpdate()
        }
        return store
    }()
    private lazy var updateCoordinator = AutomaticUpdateCheckCoordinator(
        checker: updateService,
        store: updateStore,
        showDetails: { [weak self] in
            self?.showUpdateDetails()
        },
        willPresentPrompt: { [weak self] in
            self?.hideTransientPanelsForUpdatePrompt()
        }
    )
    private lazy var windows = WindowCoordinator(
        language: language,
        pet: pet,
        aiSettings: aiSettings,
        loginItem: loginItem,
        focusTimer: focusTimer,
        chat: chat,
        maintenance: maintenance,
        music: music,
        diary: diary,
        externalAudioInterruption: externalAudioInterruption,
        quickTools: quickTools,
        updater: updateStore,
        windowActivator: windowActivator,
        onSafeUserInteraction: { [weak self] in
            self?.updateCoordinator.handleExplicitUserInteraction()
        },
        terminateForUpdate: { [weak self] in
            guard let self else { return false }
            return await self.prepareToTerminateForUpdate()
        }
    )
    private var terminationTask: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []

    func start() {
        NSApp.setActivationPolicy(.accessory)
        windows.start()
        externalAudioInterruption.start()
        updateCoordinator.start()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(forName: NSWorkspace.willPowerOffNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in _ = await self?.diary.flush() }
            },
            center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in _ = await self?.diary.flush() }
            }
        ]
    }

    func stop() {
        updateCoordinator.stop()
        externalAudioInterruption.stop()
        windows.stop()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(center.removeObserver)
        workspaceObservers.removeAll()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        terminationTask = Task { [weak self] in
            guard let self else {
                sender.reply(toApplicationShouldTerminate: true)
                return
            }
            guard await diary.flush() else {
                diary.operationError = AppLocalizer.string("diary.error.saveBeforeQuit")
                terminationTask = nil
                sender.reply(toApplicationShouldTerminate: false)
                return
            }
            externalAudioInterruption.stop()
            await music.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func prepareToTerminateForUpdate() async -> Bool {
        let saved = await diary.flush()
        if !saved { diary.operationError = AppLocalizer.string("diary.error.saveBeforeUpdate") }
        return saved
    }

    private func showUpdateDetails() {
        windows.open(.settings(.about))
    }

    private func hideTransientPanelsForUpdatePrompt() {
        windows.hideTransientPanelsForUpdatePrompt()
    }
}

@MainActor
final class WindowCoordinator: NSObject {
    private let language: AppLanguageSettings
    private let pet: PetStore
    private let aiSettings: AISettingsStore
    private let loginItem: LoginItemStore
    private let focusTimer: FocusTimerStore
    private let chat: ChatStore
    private let maintenance: MaintenanceStore
    private let music: MusicFeature
    private let diary: DiaryFeature
    private let externalAudioInterruption: ExternalAudioInterruptionController
    private let quickTools: QuickToolsController
    private let updater: AppUpdateStore
    private let windowActivator: ApplicationWindowActivating
    private let onSafeUserInteraction: () -> Void
    private let terminateForUpdate: () async -> Bool
    private var panelController: PetPanelController?
    private var statusItem: NSStatusItem?
    private var dashboardController: StatusDashboardPanelController?
    private var settingsController: SettingsWindowController?
    private var chatHistoryController: ChatHistoryWindowController?
    private var maintenanceController: MaintenanceWindowController?
    private var musicController: MusicWindowController?
    private var diaryController: DiaryWindowController?
    private var lyricsController: LyricsPanelController?
    private var weatherStartupTask: Task<Void, Never>?

    private lazy var actions = AppActions(
        open: { [weak self] route in self?.open(route) },
        runQuickTool: { [weak self] route in self?.runQuickTool(route) },
        terminateForUpdate: { [weak self] in
            guard let self else { return false }
            return await self.terminateForUpdate()
        }
    )

    init(
        language: AppLanguageSettings,
        pet: PetStore,
        aiSettings: AISettingsStore,
        loginItem: LoginItemStore,
        focusTimer: FocusTimerStore,
        chat: ChatStore,
        maintenance: MaintenanceStore,
        music: MusicFeature,
        diary: DiaryFeature,
        externalAudioInterruption: ExternalAudioInterruptionController,
        quickTools: QuickToolsController,
        updater: AppUpdateStore,
        windowActivator: ApplicationWindowActivating,
        onSafeUserInteraction: @escaping () -> Void,
        terminateForUpdate: @escaping () async -> Bool
    ) {
        self.language = language
        self.pet = pet
        self.aiSettings = aiSettings
        self.loginItem = loginItem
        self.focusTimer = focusTimer
        self.chat = chat
        self.maintenance = maintenance
        self.music = music
        self.diary = diary
        self.externalAudioInterruption = externalAudioInterruption
        self.quickTools = quickTools
        self.updater = updater
        self.windowActivator = windowActivator
        self.onSafeUserInteraction = onSafeUserInteraction
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
            appActions: actions,
            windowActivator: windowActivator
        )
        panelController?.show()
        installMenuBarItem()
        music.lyricsPresentation.onVisibilityChanged = { [weak self] in
            self?.updateLyricsVisibility()
        }
        music.lyricsPresentation.onLockChanged = { [weak self] in
            self?.lyricsController?.updateLock()
        }
        if music.lyricsPresentation.isVisible {
            updateLyricsVisibility()
        }
        weatherStartupTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            self?.pet.weather.start()
        }
        diary.onEntryCompleted = { [weak self] in self?.pet.showDiarySavedMessage() }
    }

    func stop() {
        weatherStartupTask?.cancel()
        pet.monitor.stop()
        quickTools.stop()
        music.lyricsPresentation.onVisibilityChanged = nil
        music.lyricsPresentation.onLockChanged = nil
    }

    /// The Dashboard uses the status-bar window level, which is above the
    /// floating update prompt. Hide that transient panel before the prompt is
    /// ordered front; persistent windows and desktop lyrics stay untouched.
    func hideTransientPanelsForUpdatePrompt() {
        dashboardController?.hide()
    }

    func open(_ route: AppRoute) {
        onSafeUserInteraction()

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
            Task { @MainActor [weak self] in
                await Task.yield()
                self?.showMusic()
            }
        case .diary:
            dashboardController?.hide()
            showDiary()
            Task { await diary.loadIfNeeded() }
        case .quickDiary:
            dashboardController?.hide()
            Task { [weak self] in
                guard let self else { return }
                await diary.loadIfNeeded()
                showQuickDiary()
            }
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
        let mainMenu = NSMenu(title: AppLocalizer.string("menu.main"))
        let applicationItem = NSMenuItem(title: "YuanGUI", action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu(title: "YuanGUI")
        applicationMenu.addItem(
            withTitle: AppLocalizer.string("menu.quit"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem(title: AppLocalizer.string("menu.edit"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: AppLocalizer.string("menu.edit"))
        editMenu.addItem(withTitle: AppLocalizer.string("menu.undo"), action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: AppLocalizer.string("menu.cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: AppLocalizer.string("menu.copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: AppLocalizer.string("menu.paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: AppLocalizer.string("menu.selectAll"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let toolsItem = NSMenuItem(title: AppLocalizer.string("menu.tools"), action: nil, keyEquivalent: "")
        let toolsMenu = NSMenu(title: AppLocalizer.string("menu.tools"))
        toolsMenu.addItem(withTitle: AppLocalizer.string("menu.regionScreenshot"), action: #selector(startRegionScreenshot), keyEquivalent: "")
        toolsMenu.addItem(withTitle: AppLocalizer.string("menu.screenshotTranslation"), action: #selector(startScreenshotTranslation), keyEquivalent: "")
        toolsMenu.addItem(withTitle: AppLocalizer.string("menu.translateSelection"), action: #selector(translateSelection), keyEquivalent: "")
        toolsMenu.addItem(NSMenuItem.separator())
        let diaryItem = toolsMenu.addItem(withTitle: AppLocalizer.string("手帐本"), action: #selector(showDiaryFromMenu), keyEquivalent: "d")
        diaryItem.keyEquivalentModifierMask = [.command]
        for item in toolsMenu.items { item.target = self }
        toolsItem.submenu = toolsMenu
        mainMenu.addItem(toolsItem)
        NSApp.mainMenu = mainMenu
    }

    private func installMenuBarItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "pawprint.fill",
            accessibilityDescription: AppLocalizer.string("元圭与 VCC")
        )
        statusItem.button?.target = self
        statusItem.button?.action = #selector(toggleDashboard)
        statusItem.button?.sendAction(on: [.leftMouseUp])
        self.statusItem = statusItem
    }

    @objc private func toggleDashboard() {
        onSafeUserInteraction()
        guard let button = statusItem?.button else { return }
        dashboard().toggle(relativeTo: button)
    }

    private func dashboard() -> StatusDashboardPanelController {
        if let dashboardController { return dashboardController }
        let controller = StatusDashboardPanelController(
            store: pet,
            focusTimer: focusTimer,
            music: music,
            externalAudioInterruption: externalAudioInterruption,
            quickTools: quickTools,
            updater: updater,
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
                language: language,
                petStore: pet,
                aiSettings: aiSettings,
                loginItem: loginItem,
                focusTimer: focusTimer,
                music: music,
                diary: diary,
                externalAudioInterruption: externalAudioInterruption,
                quickTools: quickTools,
                updater: updater,
                showPet: { [weak self] in self?.panelController?.show() },
                appActions: actions,
                windowActivator: windowActivator
            )
        }
        settingsController?.show(tab: tab)
    }

    private func showChatHistory() {
        if chatHistoryController == nil {
            chatHistoryController = ChatHistoryWindowController(
                chat: chat,
                windowActivator: windowActivator
            )
        }
        chatHistoryController?.show()
    }

    private func showMaintenance() {
        if maintenanceController == nil {
            maintenanceController = MaintenanceWindowController(
                store: maintenance,
                windowActivator: windowActivator
            ) { [weak self] in
                self?.maintenanceController = nil
            }
        }
        maintenanceController?.show()
    }

    private func showMusic() {
        if musicController == nil {
            musicController = MusicWindowController(
                music: music,
                appActions: actions,
                windowActivator: windowActivator,
                onClose: { [weak self] in self?.musicController = nil }
            )
        }
        musicController?.show()
    }

    private func showDiary() {
        if diaryController == nil {
            diaryController = DiaryWindowController(
                store: diary,
                windowActivator: windowActivator
            ) { [weak self] in
                self?.diaryController = nil
            }
        }
        diaryController?.show()
    }

    private func showQuickDiary() {
        if diaryController == nil {
            diaryController = DiaryWindowController(
                store: diary,
                windowActivator: windowActivator
            ) { [weak self] in
                self?.diaryController = nil
            }
        }
        diaryController?.showQuickEntry()
    }

    private func updateLyricsVisibility() {
        guard music.lyricsPresentation.isVisible else {
            lyricsController?.hide()
            return
        }
        if lyricsController == nil {
            lyricsController = LyricsPanelController(music: music)
        }
        lyricsController?.show()
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

    @objc private func showDiaryFromMenu() {
        open(.diary)
    }
}
