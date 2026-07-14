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
    private lazy var chatStore = ChatStore(settings: aiSettings)
    private var panelController: PetPanelController?
    private var statusItem: NSStatusItem?
    private var dashboardController: StatusDashboardPanelController?
    private var settingsController: SettingsWindowController?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panelController = PetPanelController(store: store, chat: chatStore)
        panelController?.show()
        settingsController = SettingsWindowController(
            petStore: store,
            aiSettings: aiSettings,
            showPet: { [weak self] in self?.panelController?.show() }
        )
        installMenuBarItem()
        chatStore.$isPresented
            .removeDuplicates()
            .sink { [weak self] presented in self?.store.setChatting(presented) }
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

        store.$smartState
            .removeDuplicates()
            .sink { [weak self] state in self?.updateStatusIcon(for: state) }
            .store(in: &cancellables)
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
                    if self.chatStore.isPresented {
                        self.panelController?.focusForChatInput()
                    }
                }
            }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .showYuanGUISettings)
            .sink { [weak self] _ in
                Task { @MainActor in self?.settingsController?.show() }
            }
            .store(in: &cancellables)
        self.statusItem = statusItem
    }

    @objc private func toggleDashboard() {
        guard let button = statusItem?.button else { return }
        dashboardController?.toggle(relativeTo: button)
    }

    private func updateStatusIcon(for state: SmartPetState) {
        let symbol: String
        switch state {
        case .normal: symbol = "pawprint.fill"
        case .lowBattery: symbol = "battery.25percent"
        case .memoryPressure: symbol = "memorychip.fill"
        case .charging: symbol = "bolt.heart.fill"
        case .rainy: symbol = "umbrella.fill"
        case .bedtime: symbol = "moon.zzz.fill"
        }
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "元圭与 VCC：\(state.rawValue)"
        )
    }
}
