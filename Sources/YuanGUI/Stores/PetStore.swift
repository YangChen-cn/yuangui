import AppKit
import Combine
import Foundation

@MainActor
final class PetStore: ObservableObject {
    @Published private(set) var mode: PetMode
    @Published var actionIndex = 0
    @Published private(set) var showsSystemStatus: Bool
    @Published private(set) var petScale: Double
    @Published private(set) var smartReactionsEnabled: Bool
    @Published private(set) var smartState: SmartPetState = .normal
    @Published private var isSmartActionSuppressed = false
    @Published var isDropTargeted = false
    @Published private(set) var toast: String?

    let monitor: SystemMonitor
    let weather: WeatherService
    private let trashHandler: TrashHandling
    private let defaults: UserDefaults
    private var idleTimer: AnyCancellable?
    private var clockTimer: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var toastToken = UUID()

    var currentAction: PetAction {
        if smartReactionsEnabled,
           !isSmartActionSuppressed,
           let action = mode.smartAction(for: smartState) {
            return action
        }
        let actions = mode.actions
        return actions[min(actionIndex, actions.count - 1)]
    }

    var shouldShowPetBubble: Bool {
        showsSystemStatus || (smartReactionsEnabled && smartState.showsAutomaticBubble)
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
        if defaults.object(forKey: "petMode") != nil {
            self.mode = PetMode(rawValue: defaults.integer(forKey: "petMode")) ?? .duo
        } else {
            self.mode = .duo
        }
        self.showsSystemStatus = defaults.bool(forKey: "showsSystemStatus")
        let savedScale = defaults.object(forKey: "petScale") as? Double ?? 1
        self.petScale = min(max(savedScale, 0.70), 1.40)
        self.smartReactionsEnabled = defaults.object(forKey: "smartReactionsEnabled") == nil
            ? true
            : defaults.bool(forKey: "smartReactionsEnabled")

        Publishers.CombineLatest(monitor.$snapshot, self.weather.$snapshot)
            .map { snapshot, weather in
                SmartPetState.resolve(system: snapshot, weather: weather, date: Date())
            }
            .removeDuplicates()
            .sink { [weak self] state in self?.applySmartState(state) }
            .store(in: &cancellables)

        if startServices {
            monitor.start()
            idleTimer = Timer.publish(every: 12, tolerance: 2, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.chooseIdleAction() }
            clockTimer = Timer.publish(every: 60, tolerance: 5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] date in self?.evaluateSmartState(at: date) }
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

    func setSmartReactionsEnabled(_ enabled: Bool) {
        smartReactionsEnabled = enabled
        defaults.set(enabled, forKey: "smartReactionsEnabled")
        if !enabled { smartState = .normal }
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

    func showSettings() {
        NotificationCenter.default.post(name: .showYuanGUISettings, object: nil)
    }

    func hideSystemStatus() {
        setSystemStatusVisible(false)
    }

    func recycle(_ urls: [URL]) {
        isDropTargeted = false
        Task { await recycleItems(urls) }
    }

    func recycleItems(_ urls: [URL]) async {
        do {
            let count = try await trashHandler.recycle(urls)
            guard count > 0 else {
                showToast("没有可移入废纸篓的项目")
                return
            }
            actionIndex = min(3, mode.actions.count - 1)
            showToast(count == 1 ? "已移入废纸篓" : "已将 \(count) 个项目移入废纸篓")
        } catch {
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
        guard !isDropTargeted, smartState == .normal else { return }
        let count = mode.actions.count
        guard count > 1 else { return }
        var next = Int.random(in: 0..<count)
        if next == actionIndex { next = (next + 1) % count }
        actionIndex = next
    }

    private func applySmartState(_ state: SmartPetState) {
        guard smartReactionsEnabled else { return }
        let previous = smartState
        smartState = state
        guard state != previous else { return }
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
        applySmartState(SmartPetState.resolve(
            system: monitor.snapshot,
            weather: weather.snapshot,
            date: date
        ))
    }
}
