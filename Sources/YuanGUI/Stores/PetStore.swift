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
    @Published private(set) var petMotionEnabled: Bool
    @Published private(set) var smartReactionsEnabled: Bool
    @Published private(set) var interactionLocked: Bool
    @Published private(set) var lockedControlsVisible = false
    @Published private(set) var bedtimeReminderEnabled: Bool
    @Published private(set) var bedtimeStartMinutes: Int
    @Published private(set) var bedtimeEndMinutes: Int
    @Published private(set) var ambientChatterEnabled: Bool
    @Published private(set) var ambientChatterIntervalMinutes: Int
    @Published private(set) var weatherAnnouncementsEnabled: Bool
    @Published private(set) var desktopIconsVisible: Bool
    @Published private(set) var smartState: SmartPetState = .normal
    @Published private(set) var activeSmartStates: [SmartPetState] = []
    @Published private(set) var isChatting = false
    @Published private var isSmartActionSuppressed = false
    @Published private(set) var automaticBubbleSuppressed = false
    @Published var isDropTargeted = false
    @Published private(set) var toast: String?
    @Published private(set) var ambientMessage: String?
    @Published private(set) var taskState: TaskState = .idle
    @Published private(set) var taskMessage: String?
    @Published private(set) var isPetPresented = false

    let monitor: SystemMonitor
    let weather: WeatherService
    private let trashHandler: TrashHandling
    private let desktopIconManager: DesktopIconManaging
    private let defaults: UserDefaults
    private let taskAnimationsEnabled: Bool
    private var minuteTimer: AnyCancellable?
    private var smartRotationTimer: AnyCancellable?
    private var smartActionSuppressionTask: Task<Void, Never>?
    private var lockedControlsHideTask: Task<Void, Never>?
    private var ambientChatterTask: Task<Void, Never>?
    private var ambientMessageHideTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var toastToken = UUID()
    private var lastAmbientMessage: String?

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
        showsSystemStatus || (!automaticBubbleSuppressed && smartReactionsEnabled && activeSmartStates.contains(where: \.showsAutomaticBubble))
    }

    var shouldReservePetBubbleSpace: Bool {
        shouldShowPetBubble || ambientMessage != nil
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
        desktopIconManager: DesktopIconManaging? = nil,
        defaults: UserDefaults = .standard,
        startServices: Bool = true
    ) {
        self.monitor = monitor
        self.weather = weather ?? WeatherService()
        self.trashHandler = trashHandler
        let desktopIconManager = desktopIconManager ?? DesktopIconService()
        self.desktopIconManager = desktopIconManager
        self.desktopIconsVisible = desktopIconManager.areDesktopIconsVisible()
        self.defaults = defaults
        self.taskAnimationsEnabled = startServices
        if defaults.object(forKey: "petMode") != nil {
            self.mode = PetMode(rawValue: defaults.integer(forKey: "petMode")) ?? .duo
        } else {
            self.mode = .duo
        }
        self.showsSystemStatus = defaults.bool(forKey: "showsSystemStatus")
        let savedScale = defaults.object(forKey: "petScale") as? Double ?? PetLayout.defaultScale
        self.petScale = min(max(savedScale, PetLayout.minimumScale), PetLayout.maximumScale)
        self.dashboardStyle = DashboardStyle(rawValue: defaults.integer(forKey: "dashboardStyle")) ?? .softGlass
        self.idleAnimationEnabled = defaults.object(forKey: "idleAnimationEnabled") == nil
            ? true
            : defaults.bool(forKey: "idleAnimationEnabled")
        self.petMotionEnabled = defaults.object(forKey: "petMotionEnabled") == nil
            ? true
            : defaults.bool(forKey: "petMotionEnabled")
        self.smartReactionsEnabled = defaults.object(forKey: "smartReactionsEnabled") == nil
            ? true
            : defaults.bool(forKey: "smartReactionsEnabled")
        let initiallyLocked = defaults.bool(forKey: "interactionLocked")
        self.interactionLocked = initiallyLocked
        self.bedtimeReminderEnabled = defaults.object(forKey: "bedtimeReminderEnabled") == nil
            ? true : defaults.bool(forKey: "bedtimeReminderEnabled")
        self.bedtimeStartMinutes = defaults.object(forKey: "bedtimeStartMinutes") as? Int ?? 23 * 60
        self.bedtimeEndMinutes = defaults.object(forKey: "bedtimeEndMinutes") as? Int ?? 5 * 60
        self.ambientChatterEnabled = defaults.object(forKey: "ambientChatterEnabled") == nil
            ? true : defaults.bool(forKey: "ambientChatterEnabled")
        let savedChatterInterval = defaults.object(forKey: "ambientChatterIntervalMinutes") as? Int ?? 15
        self.ambientChatterIntervalMinutes = min(max(savedChatterInterval, 1), 120)
        self.weatherAnnouncementsEnabled = defaults.object(forKey: "weatherAnnouncementsEnabled") == nil
            ? true : defaults.bool(forKey: "weatherAnnouncementsEnabled")
        self.lockedControlsVisible = initiallyLocked

        Publishers.CombineLatest(monitor.$snapshot, self.weather.$snapshot)
            .map { [weak self] snapshot, weather in
                SmartPetState.resolveAll(
                    system: snapshot, weather: weather, date: Date(),
                    bedtimeEnabled: self?.bedtimeReminderEnabled ?? true,
                    bedtimeStartMinutes: self?.bedtimeStartMinutes ?? 23 * 60,
                    bedtimeEndMinutes: self?.bedtimeEndMinutes ?? 5 * 60
                )
            }
            .removeDuplicates()
            .sink { [weak self] states in self?.applySmartStates(states) }
            .store(in: &cancellables)

        self.weather.$snapshot
            .compactMap { $0 }
            .sink { [weak self] snapshot in self?.presentWeatherRefreshAnnouncement(snapshot) }
            .store(in: &cancellables)

        if startServices {
            monitor.start()
            syncMiniMonitoringDemand()
            self.weather.start()
            minuteTimer = Timer.publish(every: 60, tolerance: 8, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] date in
                    self?.chooseIdleAction()
                    self?.evaluateSmartState(at: date)
                }
        }
        if interactionLocked {
            scheduleLockedControlsHide(after: 3)
        }
    }

    func setMode(_ newMode: PetMode) {
        mode = newMode
        actionIndex = 0
        defaults.set(newMode.rawValue, forKey: "petMode")
        showToast("切换到「\(newMode.title)」")
    }

    func interact() {
        guard !interactionLocked else { return }
        actionIndex = (actionIndex + 1) % mode.actions.count
        if smartState != .normal {
            smartActionSuppressionTask?.cancel()
            isSmartActionSuppressed = true
            smartActionSuppressionTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 6_000_000_000) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.isSmartActionSuppressed = false
                self?.smartActionSuppressionTask = nil
            }
        }
        showToast(currentAction.label)
    }

    func setPetScale(_ scale: Double) {
        petScale = min(max(scale, PetLayout.minimumScale), PetLayout.maximumScale)
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

    func setPetMotionEnabled(_ enabled: Bool) {
        petMotionEnabled = enabled
        defaults.set(enabled, forKey: "petMotionEnabled")
    }

    func setPetPresented(_ presented: Bool) {
        guard isPetPresented != presented else { return }
        isPetPresented = presented
        ambientChatterTask?.cancel()
        ambientChatterTask = nil
        if presented {
            if ambientChatterEnabled { scheduleNextAmbientChatter(initial: true) }
        } else {
            dismissAmbientMessage()
        }
    }

    func setAmbientChatterEnabled(_ enabled: Bool) {
        ambientChatterEnabled = enabled
        defaults.set(enabled, forKey: "ambientChatterEnabled")
        ambientChatterTask?.cancel()
        ambientChatterTask = nil
        if enabled, isPetPresented { scheduleNextAmbientChatter(initial: true) }
    }

    func setAmbientChatterIntervalMinutes(_ minutes: Int) {
        ambientChatterIntervalMinutes = min(max(minutes, 1), 120)
        defaults.set(ambientChatterIntervalMinutes, forKey: "ambientChatterIntervalMinutes")
        if ambientChatterEnabled, isPetPresented { scheduleNextAmbientChatter() }
    }

    func setWeatherAnnouncementsEnabled(_ enabled: Bool) {
        weatherAnnouncementsEnabled = enabled
        defaults.set(enabled, forKey: "weatherAnnouncementsEnabled")
    }

    func setSmartReactionsEnabled(_ enabled: Bool) {
        smartReactionsEnabled = enabled
        defaults.set(enabled, forKey: "smartReactionsEnabled")
        if !enabled {
            activeSmartStates = []
            smartState = .normal
            smartRotationTimer = nil
            syncMiniMonitoringDemand()
        }
        if enabled { evaluateSmartState() }
    }

    func setInteractionLocked(_ locked: Bool) {
        lockedControlsHideTask?.cancel()
        interactionLocked = locked
        lockedControlsVisible = locked
        defaults.set(locked, forKey: "interactionLocked")
        showToast(locked ? "已锁定，点击会穿透桌宠" : "已解锁桌宠")
        if locked {
            scheduleLockedControlsHide(after: 3)
        }
    }

    func toggleInteractionLock() { setInteractionLocked(!interactionLocked) }

    func revealLockedControls() {
        guard interactionLocked else { return }
        lockedControlsHideTask?.cancel()
        lockedControlsHideTask = nil
        if !lockedControlsVisible {
            lockedControlsVisible = true
        }
    }

    func scheduleLockedControlsHide(after seconds: Double = 0.8) {
        guard interactionLocked else { return }
        lockedControlsHideTask?.cancel()
        let delay = UInt64(max(seconds, 0) * 1_000_000_000)
        lockedControlsHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self, self.interactionLocked else { return }
            self.lockedControlsHideTask = nil
            self.lockedControlsVisible = false
        }
    }

    func toggleSystemStatus() {
        if shouldShowPetBubble {
            automaticBubbleSuppressed = true
            setSystemStatusVisible(false)
        } else {
            automaticBubbleSuppressed = false
            setSystemStatusVisible(true)
        }
    }

    func showFullDashboard() {
        NotificationCenter.default.post(name: .showYuanGUIDashboard, object: nil)
    }

    func showChat() {
        NotificationCenter.default.post(name: .showYuanGUIChat, object: nil)
    }

    func setChatting(_ chatting: Bool) {
        isChatting = chatting
        if chatting { dismissAmbientMessage() }
    }

    func showSettings() {
        NotificationCenter.default.post(name: .showYuanGUISettings, object: nil)
    }

    func showMaintenance(tab: Int = 0) {
        NotificationCenter.default.post(name: .showYuanGUIMaintenance, object: nil, userInfo: ["tab": tab])
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
        automaticBubbleSuppressed = true
        setSystemStatusVisible(false)
    }

    func setBedtimeReminderEnabled(_ enabled: Bool) {
        bedtimeReminderEnabled = enabled
        defaults.set(enabled, forKey: "bedtimeReminderEnabled")
        evaluateSmartState()
    }

    func setBedtimeStartMinutes(_ minutes: Int) {
        bedtimeStartMinutes = min(max(minutes, 0), 1_439)
        defaults.set(bedtimeStartMinutes, forKey: "bedtimeStartMinutes")
        evaluateSmartState()
    }

    func setBedtimeEndMinutes(_ minutes: Int) {
        bedtimeEndMinutes = min(max(minutes, 0), 1_439)
        defaults.set(bedtimeEndMinutes, forKey: "bedtimeEndMinutes")
        evaluateSmartState()
    }

    func recycle(_ urls: [URL]) {
        isDropTargeted = false
        Task { await recycleItems(urls) }
    }

    func recycleItems(_ urls: [URL]) async {
        dismissAmbientMessage()
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

    func refreshDesktopIconVisibility() {
        desktopIconsVisible = desktopIconManager.areDesktopIconsVisible()
    }

    func toggleDesktopIcons() {
        let visible = !desktopIconsVisible
        do {
            try desktopIconManager.setDesktopIconsVisible(visible)
            desktopIconsVisible = visible
            showToast(visible ? "已显示桌面图标" : "已隐藏桌面图标")
        } catch {
            desktopIconsVisible = desktopIconManager.areDesktopIconsVisible()
            NSSound.beep()
            showToast("切换桌面图标失败：\(error.localizedDescription)")
        }
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
        dismissAmbientMessage()
        let token = UUID()
        toastToken = token
        toast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self, self.toastToken == token else { return }
            self.toast = nil
        }
    }

    func setSystemStatusVisible(_ visible: Bool) {
        if visible { automaticBubbleSuppressed = false }
        showsSystemStatus = visible
        syncMiniMonitoringDemand()
        defaults.set(visible, forKey: "showsSystemStatus")
        if visible {
            monitor.refresh()
            if mode == .yuanGui { actionIndex = 5 }
            if mode == .duo { actionIndex = 6 }
        }
    }

    private func chooseIdleAction() {
        guard isPetPresented, idleAnimationEnabled, taskState == .idle,
              !isDropTargeted, !isChatting, activeSmartStates.isEmpty else { return }
        let count = mode.actions.count
        guard count > 1 else { return }
        actionIndex = (actionIndex + 1) % count
    }

    func applySmartStates(_ states: [SmartPetState]) {
        guard smartReactionsEnabled else { return }
        let previousStates = activeSmartStates
        let newlyActivatedStates = states.filter { !previousStates.contains($0) }
        activeSmartStates = states
        if states != previousStates {
            automaticBubbleSuppressed = false
            smartActionSuppressionTask?.cancel()
            smartActionSuppressionTask = nil
            isSmartActionSuppressed = false
        }
        if let urgentState = newlyActivatedStates.first(where: \.isUrgent) {
            smartState = urgentState
        } else if let newlyActivatedState = newlyActivatedStates.first {
            smartState = newlyActivatedState
        } else if let currentIndex = states.firstIndex(of: smartState) {
            smartState = states[currentIndex]
        } else {
            smartState = states.first ?? .normal
        }
        syncMiniMonitoringDemand()
        updateSmartRotationTimer()
        guard states != previousStates, smartState != .normal else { return }
        showSmartMessage(smartState)
    }

    private func rotateSmartState() {
        guard smartReactionsEnabled, activeSmartStates.count > 1, !isChatting else { return }
        let index = activeSmartStates.firstIndex(of: smartState) ?? -1
        smartState = activeSmartStates[(index + 1) % activeSmartStates.count]
    }

    private func updateSmartRotationTimer() {
        let shouldRun = smartReactionsEnabled && activeSmartStates.count > 1
        if shouldRun, smartRotationTimer == nil {
            smartRotationTimer = Timer.publish(every: 30, tolerance: 5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.rotateSmartState() }
        } else if !shouldRun {
            smartRotationTimer = nil
        }
    }

    private func syncMiniMonitoringDemand() {
        monitor.setMiniStatusVisible(shouldShowPetBubble)
    }

    private func showSmartMessage(_ state: SmartPetState) {
        switch state {
        case .lowBattery:
            let percent = monitor.snapshot.battery?.chargeFraction.map(MetricFormatting.percent) ?? "低电量"
            showAmbientMessage("master，Mac 只剩 \(percent) 电量啦，VCC 正叼着充电线跑来～")
        case .memoryPressure:
            showAmbientMessage("master，现在内存有点挤，元圭陪你看看要不要休息一下应用吧～")
        case .charging:
            if let minutes = monitor.snapshot.battery?.timeRemainingMinutes, minutes > 0 {
                showAmbientMessage("正在充电，再过约 \(ambientDurationText(minutes))就满啦～")
            } else {
                showAmbientMessage("充电中，元圭和 VCC 正在陪 Mac 补充能量～")
            }
        case .rainy:
            if let snapshot = weather.snapshot,
               let message = PetAmbientChatter.weatherAnnouncements(
                   mode: mode,
                   weather: snapshot,
                   locationName: weather.locationName
               ).randomElement() {
                showAmbientMessage(message, duration: 10)
            } else {
                showAmbientMessage("外面下雨啦，master 出门记得带伞，VCC 不可以踩水坑哦～")
            }
        case .bedtime:
            showAmbientMessage("夜深了，master 该休息啦，元圭和 VCC 陪你说晚安～")
        case .normal:
            break
        }
    }

    func dismissAmbientMessage() {
        ambientMessageHideTask?.cancel()
        ambientMessageHideTask = nil
        ambientMessage = nil
    }

    func showAmbientMessage(_ message: String, duration: TimeInterval = 8) {
        guard isPetPresented, taskState == .idle, !isDropTargeted, !isChatting else { return }
        let value = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        toastToken = UUID()
        toast = nil
        ambientMessageHideTask?.cancel()
        ambientMessage = value
        lastAmbientMessage = value
        let nanoseconds = UInt64(max(duration, 0) * 1_000_000_000)
        ambientMessageHideTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: nanoseconds) }
            catch { return }
            guard !Task.isCancelled, let self, self.ambientMessage == value else { return }
            self.ambientMessageHideTask = nil
            self.ambientMessage = nil
        }
    }

    private func scheduleNextAmbientChatter(initial: Bool = false) {
        guard taskAnimationsEnabled, ambientChatterEnabled, isPetPresented else { return }
        ambientChatterTask?.cancel()
        let configuredDelay = TimeInterval(ambientChatterIntervalMinutes * 60)
        let delay = initial ? min(configuredDelay, 180) : configuredDelay
        ambientChatterTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
            catch { return }
            guard !Task.isCancelled, let self else { return }
            self.presentScheduledAmbientChatter()
            self.scheduleNextAmbientChatter()
        }
    }

    private func presentScheduledAmbientChatter() {
        guard taskState == .idle,
              !isDropTargeted,
              !isChatting,
              toast == nil,
              ambientMessage == nil else { return }
        let candidates = PetAmbientChatter.candidates(
            mode: mode,
            system: monitor.snapshot,
            weather: weather.snapshot,
            locationName: weather.locationName
        ).filter { $0 != lastAmbientMessage }
        guard let message = candidates.randomElement() else { return }
        showAmbientMessage(message)
    }

    private func presentWeatherRefreshAnnouncement(_ snapshot: WeatherSnapshot) {
        guard taskAnimationsEnabled,
              ambientChatterEnabled,
              weatherAnnouncementsEnabled,
              taskState == .idle,
              !isDropTargeted,
              !isChatting,
              toast == nil,
              ambientMessage == nil else { return }
        let messages = PetAmbientChatter.weatherAnnouncements(
            mode: mode,
            weather: snapshot,
            locationName: weather.locationName
        ).filter { $0 != lastAmbientMessage }
        guard let message = messages.randomElement() else { return }
        showAmbientMessage(message, duration: 10)
    }

    private func ambientDurationText(_ totalMinutes: Int) -> String {
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 { return "\(hours)小时\(minutes)分钟" }
        if hours > 0 { return "\(hours)小时" }
        return "\(minutes)分钟"
    }

    private func evaluateSmartState(at date: Date = Date()) {
        applySmartStates(SmartPetState.resolveAll(
            system: monitor.snapshot,
            weather: weather.snapshot,
            date: date,
            bedtimeEnabled: bedtimeReminderEnabled,
            bedtimeStartMinutes: bedtimeStartMinutes,
            bedtimeEndMinutes: bedtimeEndMinutes
        ))
    }
}
