import AppKit
import Combine
import Foundation

@MainActor
final class PetStore: ObservableObject {
    enum TaskState: Equatable {
        case idle
        case maintenance
        case maintenanceSuccess
        case recycling(Int)
    }
    @Published private(set) var mode: PetMode
    @Published var actionIndex = 0
    @Published private(set) var showsSystemStatus: Bool
    @Published private(set) var petScale: Double
    @Published private(set) var dashboardStyle: DashboardStyle
    @Published private(set) var idleAnimationEnabled: Bool
    @Published private(set) var smartReactionsEnabled: Bool
    @Published private(set) var smartState: SmartPetState = .normal
    @Published private(set) var activeSmartStates: [SmartPetState] = []
    @Published private(set) var isChatting = false
    @Published private var isSmartActionSuppressed = false
    @Published var isDropTargeted = false
    @Published private(set) var toast: String?
    @Published private(set) var taskState: TaskState = .idle
    @Published private(set) var taskMessage: String?

    let monitor: SystemMonitor
    let weather: WeatherService
    private let trashHandler: TrashHandling
    private let defaults: UserDefaults
    private let taskAnimationsEnabled: Bool
    private var idleTimer: AnyCancellable?
    private var clockTimer: AnyCancellable?
    private var smartRotationTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var toastToken = UUID()

    var currentAction: PetAction {
        switch taskState {
        case .maintenance: return PetAction(file: "18-maintenance-scan", label: "正在扫描")
        case .maintenanceSuccess: return PetAction(file: "19-maintenance-success", label: "清理完成")
        case .recycling(let frame): return PetAction(file: "15-eat-trash-\(min(max(frame, 1), 3))", label: "把文件吃掉啦")
        case .idle: break
        }
        if isChatting { return mode.chatAction }
        if smartReactionsEnabled,
           !isSmartActionSuppressed,
           let action = mode.smartAction(for: smartState) {
            return action
        }
        let actions = mode.actions
        return actions[min(actionIndex, actions.count - 1)]
    }

    var shouldShowPetBubble: Bool {
        showsSystemStatus || (smartReactionsEnabled && activeSmartStates.contains(where: \.showsAutomaticBubble))
    }

    convenience init() {
        self.init(
            monitor: SystemMonitor(),
            weather: WeatherService(),
            trashHandler: TrashService(),
            defaults: .standard,
            startServices: true
        )
    }

    init(
        monitor: SystemMonitor,
        weather: WeatherService? = nil,
        trashHandler: TrashHandling,
        defaults: UserDefaults = .standard,
        startServices: Bool = true
    ) {
        self.monitor = monitor
        self.weather = weather ?? WeatherService()
        self.trashHandler = trashHandler
        self.defaults = defaults
        self.taskAnimationsEnabled = startServices
        if defaults.object(forKey: "petMode") != nil {
            self.mode = PetMode(rawValue: defaults.integer(forKey: "petMode")) ?? .duo
        } else {
            self.mode = .duo
        }
        self.showsSystemStatus = defaults.bool(forKey: "showsSystemStatus")
        let savedScale = defaults.object(forKey: "petScale") as? Double ?? 1
        self.petScale = min(max(savedScale, 0.70), 1.40)
        self.dashboardStyle = DashboardStyle(rawValue: defaults.integer(forKey: "dashboardStyle")) ?? .softGlass
        self.idleAnimationEnabled = defaults.object(forKey: "idleAnimationEnabled") == nil
            ? true
            : defaults.bool(forKey: "idleAnimationEnabled")
        self.smartReactionsEnabled = defaults.object(forKey: "smartReactionsEnabled") == nil
            ? true
            : defaults.bool(forKey: "smartReactionsEnabled")

        Publishers.CombineLatest(monitor.$snapshot, self.weather.$snapshot)
            .map { snapshot, weather in
                SmartPetState.resolveAll(system: snapshot, weather: weather, date: Date())
            }
            .removeDuplicates()
            .sink { [weak self] states in self?.applySmartStates(states) }
            .store(in: &cancellables)

        if startServices {
            monitor.start()
            idleTimer = Timer.publish(every: 60, tolerance: 5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.chooseIdleAction() }
            clockTimer = Timer.publish(every: 60, tolerance: 5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] date in self?.evaluateSmartState(at: date) }
            smartRotationTimer = Timer.publish(every: 10, tolerance: 1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.rotateSmartState() }
        }
    }

    func setMode(_ newMode: PetMode) {
        mode = newMode
        actionIndex = 0
        defaults.set(newMode.rawValue, forKey: "petMode")
        showToast("切换到「\(newMode.title)」")
    }

    func interact() {
        actionIndex = (actionIndex + 1) % mode.actions.count
        if smartState != .normal {
            isSmartActionSuppressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                self?.isSmartActionSuppressed = false
            }
        }
        showToast(currentAction.label)
    }

    func setPetScale(_ scale: Double) {
        petScale = min(max(scale, 0.70), 1.40)
        defaults.set(petScale, forKey: "petScale")
    }

    func adjustPetScale(by delta: Double) {
        setPetScale(petScale + delta)
    }

    func setDashboardStyle(_ style: DashboardStyle) {
        dashboardStyle = style
        defaults.set(style.rawValue, forKey: "dashboardStyle")
    }

    func setIdleAnimationEnabled(_ enabled: Bool) {
        idleAnimationEnabled = enabled
        defaults.set(enabled, forKey: "idleAnimationEnabled")
    }

    func setSmartReactionsEnabled(_ enabled: Bool) {
        smartReactionsEnabled = enabled
        defaults.set(enabled, forKey: "smartReactionsEnabled")
        if !enabled {
            activeSmartStates = []
            smartState = .normal
        }
        if enabled { evaluateSmartState() }
    }

    func toggleSystemStatus() {
        setSystemStatusVisible(!showsSystemStatus)
    }

    func showFullDashboard() {
        NotificationCenter.default.post(name: .showYuanGUIDashboard, object: nil)
    }

    func showChat() {
        NotificationCenter.default.post(name: .showYuanGUIChat, object: nil)
    }

    func setChatting(_ chatting: Bool) {
        isChatting = chatting
    }

    func showSettings() {
        NotificationCenter.default.post(name: .showYuanGUISettings, object: nil)
    }

    func showMaintenance() {
        NotificationCenter.default.post(name: .showYuanGUIMaintenance, object: nil)
    }

    func beginMaintenance(message: String) {
        taskMessage = message
        taskState = .maintenance
        showToast(message)
    }

    func endMaintenance(message: String, success: Bool) {
        taskMessage = message
        taskState = success ? .maintenanceSuccess : .idle
        showToast(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, self.taskMessage == message else { return }
            self.taskState = .idle
            self.taskMessage = nil
        }
    }

    func hideSystemStatus() {
        setSystemStatusVisible(false)
    }

    func recycle(_ urls: [URL]) {
        isDropTargeted = false
        Task { await recycleItems(urls) }
    }

    func recycleItems(_ urls: [URL]) async {
        taskState = .recycling(1)
        taskMessage = "啊呜——VCC 和元圭接住啦！"
        do {
            let count = try await trashHandler.recycle(urls)
            guard count > 0 else {
                taskState = .idle
                taskMessage = nil
                showToast("没有可移入废纸篓的项目")
                return
            }
            taskState = .recycling(2)
            if taskAnimationsEnabled { try? await Task.sleep(nanoseconds: 380_000_000) }
            taskState = .recycling(3)
            if taskAnimationsEnabled { try? await Task.sleep(nanoseconds: 650_000_000) }
            taskState = .idle
            taskMessage = nil
            showToast(count == 1 ? "已移入废纸篓" : "已将 \(count) 个项目移入废纸篓")
        } catch {
            taskState = .idle
            taskMessage = nil
            actionIndex = min(2, mode.actions.count - 1)
            NSSound.beep()
            showToast("失败：\(error.localizedDescription)")
        }
    }

    func openTrash() {
        trashHandler.openTrash()
    }

    func confirmAndEmptyTrash() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "确定清空废纸篓？"
        alert.informativeText = "此操作不可撤销。macOS 可能会请求允许控制 Finder。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try trashHandler.emptyTrash()
            showToast("废纸篓已清空")
        } catch {
            NSSound.beep()
            showToast("无法清空：\(error.localizedDescription)。可先打开废纸篓手动处理。")
        }
    }

    func showToast(_ message: String) {
        let token = UUID()
        toastToken = token
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self, self.toastToken == token else { return }
            self.toast = nil
        }
    }

    private func setSystemStatusVisible(_ visible: Bool) {
        showsSystemStatus = visible
        defaults.set(visible, forKey: "showsSystemStatus")
        if visible {
            monitor.refresh()
            if mode == .yuanGui { actionIndex = 5 }
            if mode == .duo { actionIndex = 6 }
        }
    }

    private func chooseIdleAction() {
        guard idleAnimationEnabled, taskState == .idle, !isDropTargeted, !isChatting, activeSmartStates.isEmpty else { return }
        let count = mode.actions.count
        guard count > 1 else { return }
        actionIndex = (actionIndex + 1) % count
    }

    private func applySmartStates(_ states: [SmartPetState]) {
        guard smartReactionsEnabled else { return }
        let previousStates = activeSmartStates
        activeSmartStates = states
        if let currentIndex = states.firstIndex(of: smartState) {
            smartState = states[currentIndex]
        } else {
            smartState = states.first ?? .normal
        }
        guard states != previousStates, let first = states.first else { return }
        showSmartToast(first)
    }

    private func rotateSmartState() {
        guard smartReactionsEnabled, activeSmartStates.count > 1, !isChatting else { return }
        let index = activeSmartStates.firstIndex(of: smartState) ?? -1
        smartState = activeSmartStates[(index + 1) % activeSmartStates.count]
    }

    private func showSmartToast(_ state: SmartPetState) {
        switch state {
        case .lowBattery:
            let percent = monitor.snapshot.battery?.chargeFraction.map(MetricFormatting.percent) ?? "低电量"
            showToast("只剩 \(percent)，快接上电源吧！")
        case .memoryPressure:
            showToast("内存有点挤，我来提醒你啦")
        case .charging:
            showToast("充电中，正在补充能量～")
        case .rainy:
            showToast("外面下雨啦，出门记得带伞～")
        case .bedtime:
            showToast("夜深了，该休息啦，晚安～")
        case .normal:
            break
        }
    }

    private func evaluateSmartState(at date: Date = Date()) {
        applySmartStates(SmartPetState.resolveAll(
            system: monitor.snapshot,
            weather: weather.snapshot,
            date: date
        ))
    }
}
