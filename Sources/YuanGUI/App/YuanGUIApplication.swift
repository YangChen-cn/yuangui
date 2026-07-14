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
    private lazy var chatStore = ChatStore(settings: aiSettings)
    private lazy var maintenanceStore = MaintenanceStore(pet: store)
    private var panelController: PetPanelController?
    private var statusItem: NSStatusItem?
    private var dashboardController: StatusDashboardPanelController?
    private var settingsController: SettingsWindowController?
    private var chatHistoryController: ChatHistoryWindowController?
    private var maintenanceController: MaintenanceWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = PetPanelController(store: store, chat: chatStore, maintenance: maintenanceStore)
        panelController?.show()
        settingsController = SettingsWindowController(
            petStore: store,
            aiSettings: aiSettings,
            loginItem: loginItemStore,
            showPet: { [weak self] in self?.panelController?.show() }
        )
        chatHistoryController = ChatHistoryWindowController(chat: chatStore)
        maintenanceController = MaintenanceWindowController(store: maintenanceStore)
        installMenuBarItem()
        chatStore.$isPresented
            .removeDuplicates()
            .sink { [weak self] presented in
                self?.store.setChatting(presented)
                if presented { self?.panelController?.focusForChatInput() }
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
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

        dashboardController = StatusDashboardPanelController(
            store: store,
            togglePet: { [weak self] in self?.panelController?.toggle() },
            showPet: { [weak self] in self?.panelController?.show() },
            openSettings: { [weak self] in self?.settingsController?.show() }
        )

        NotificationCenter.default.publisher(for: .showYuanGUIDashboard)
            .sink { [weak self] _ in
                Task { @MainActor in
                    guard let self, let button = self.statusItem?.button else { return }
                    self.dashboardController?.show(relativeTo: button)
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
                Task { @MainActor in self?.settingsController?.show() }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .showYuanGUIChatHistory)
            .sink { [weak self] _ in
                Task { @MainActor in self?.chatHistoryController?.show() }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .showYuanGUIMaintenance)
            .sink { [weak self] notification in
                Task { @MainActor in
                    self?.maintenanceStore.selectTab(notification.userInfo?["tab"] as? Int ?? 0)
                    self?.maintenanceController?.show()
                }
            }
            .store(in: &cancellables)
        self.statusItem = statusItem
    }

    @objc private func toggleDashboard() {
        guard let button = statusItem?.button else { return }
        dashboardController?.toggle(relativeTo: button)
    }

}
