import AppKit
import ServiceManagement

enum LoginItemStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

protocol LoginItemManaging {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

struct LoginItemService: LoginItemManaging {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .notRegistered: return .disabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .unavailable
        @unknown default: return .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }
}

@MainActor
final class LoginItemStore: ObservableObject {
    @Published private(set) var status: LoginItemStatus
    @Published private(set) var message: String?
    private let service: LoginItemManaging

    init(service: LoginItemManaging = LoginItemService()) {
        self.service = service
        self.status = service.status
    }

    var isEnabled: Bool { status == .enabled || status == .requiresApproval }
    var isInApplicationsFolder: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/") ||
            Bundle.main.bundleURL.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/")
    }

    func refresh() { status = service.status }

    func setEnabled(_ enabled: Bool) {
        do {
            try service.setEnabled(enabled)
            status = service.status
            message = status == .requiresApproval
                ? "已添加，但需要你在系统设置中批准"
                : (enabled ? "已开启登录时自动启动" : "已关闭登录时自动启动")
        } catch {
            status = service.status
            message = "登录项设置失败：\(error.localizedDescription)"
        }
    }

    func openSystemSettings() { service.openSystemSettings() }
}
