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
    private var panelController: PetPanelController?
    private var statusItem: NSStatusItem?
    private var dashboardController: StatusDashboardPanelController?
    private var settingsController: SettingsWindowController?
    private var chatHistoryController: ChatHistoryWindowController?
    private var maintenanceController: MaintenanceWindowController?
    private var weatherStartupTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = PetPanelController(store: store, chat: chatStore, maintenance: maintenanceStore, focusTimer: focusTimer)
        panelController?.show()
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

    func applicationWillTerminate(_ notification: Notification) {
        weatherStartupTask?.cancel()
        store.monitor.stop()
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
        self.statusItem = statusItem
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

}
