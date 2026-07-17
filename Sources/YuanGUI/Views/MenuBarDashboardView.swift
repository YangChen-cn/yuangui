import AppKit
import SwiftUI

struct MenuBarDashboardView: View {
    static let preferredWidth: CGFloat = 400

    @ObservedObject var store: PetStore
    @ObservedObject var focusTimer: FocusTimerStore
    @ObservedObject var music: MusicStore
    let dashboardWidth: CGFloat
    let dashboardHeight: CGFloat
    let togglePet: () -> Void
    let showPet: () -> Void
    let openSettings: () -> Void
    let dismiss: () -> Void
    @State private var showsFocusPopover = false
    @State private var selectedSection: DashboardSection = .mac

    private enum DashboardSection: String, CaseIterable, Identifiable {
        case mac = "Mac 状态"
        case music = "音乐"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("元圭与 VCC")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("桌宠与 Mac 状态")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { showsFocusPopover.toggle() } label: {
                    ZStack {
                        Circle().fill(.red.opacity(focusTimer.state == .running ? 0.18 : 0.10))
                        Text("🍅").font(.system(size: 14))
                    }
                    .frame(width: 27, height: 27)
                }
                .buttonStyle(.plain)
                .help(focusTimer.state == .running ? "专注中：\(focusTimer.timeText)" : "打开番茄钟")
                .popover(isPresented: $showsFocusPopover, arrowEdge: .top) {
                    FocusTimerControlView(timer: focusTimer, showPet: showPet)
                }
                Label(smartStateTitle, systemImage: smartStateIcon)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(smartStateColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(smartStateColor.opacity(0.10), in: Capsule())
            }
            .padding(.horizontal, 4)

            Picker("面板内容", selection: $selectedSection) {
                ForEach(DashboardSection.allCases) { section in Text(section.rawValue).tag(section) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if selectedSection == .mac {
                WeatherStatusCard(weather: store.weather)
                SystemStatusCard(monitor: store.monitor)
            } else {
                MusicStatusCard(music: music)
                    .frame(maxHeight: .infinity)
            }

            HStack(spacing: 8) {
                dashboardTextButton("显示/隐藏桌宠", action: togglePet)
                dashboardTextButton(store.shouldShowPetBubble ? "隐藏迷你状态" : "显示迷你状态") {
                    store.toggleSystemStatus()
                    showPet()
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Button {
                        store.toggleDesktopIcons()
                    } label: {
                        Image(systemName: store.desktopIconsVisible ? "rectangle.grid.2x2.fill" : "rectangle.grid.2x2")
                    }
                    .help(store.desktopIconsVisible ? "隐藏桌面图标" : "显示桌面图标")
                    Button {
                        store.toggleInteractionLock()
                        showPet()
                    } label: {
                        Image(systemName: store.interactionLocked ? "lock.fill" : "lock.open.fill")
                    }
                    .help(store.interactionLocked ? "解锁桌宠点击" : "锁定桌宠并允许点击穿透")
                    Button {
                        dismiss()
                        store.showMaintenance()
                    } label: {
                        Image(systemName: "house.fill")
                    }
                    .help("打开元圭与 VCC 清理屋")
                    Button(action: openSettings) {
                        Image(systemName: "gearshape.fill")
                    }
                    .help("设置")
                    Menu {
                        Button("打开废纸篓") { store.openTrash() }
                        Button("清空废纸篓…") { store.confirmAndEmptyTrash() }
                        Divider()
                        Button("退出") { NSApp.terminate(nil) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 28)
                }
                .font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: true, vertical: false)
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(width: dashboardWidth, height: dashboardHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(themeGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.35), lineWidth: 0.8))
        .preferredColorScheme(store.dashboardStyle == .midnight ? .dark : nil)
        .onAppear {
            store.refreshDesktopIconVisibility()
            store.monitor.refresh()
        }
        .onExitCommand(perform: dismiss)
    }

    private func dashboardTextButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .fixedSize(horizontal: true, vertical: false)
        .layoutPriority(2)
    }

    private var smartStateTitle: String {
        switch store.smartState {
        case .normal: return "状态正常"
        case .lowBattery: return "低电量"
        case .memoryPressure: return "内存紧张"
        case .charging: return "充电中"
        case .rainy: return "下雨了"
        case .bedtime: return "该睡觉了"
        }
    }

    private var smartStateIcon: String {
        switch store.smartState {
        case .normal: return "checkmark.circle.fill"
        case .lowBattery: return "battery.25percent"
        case .memoryPressure: return "memorychip.fill"
        case .charging: return "bolt.heart.fill"
        case .rainy: return "umbrella.fill"
        case .bedtime: return "moon.zzz.fill"
        }
    }

    private var smartStateColor: Color {
        switch store.smartState {
        case .normal: return .green
        case .lowBattery: return .orange
        case .memoryPressure: return .red
        case .charging: return .mint
        case .rainy: return .blue
        case .bedtime: return .indigo
        }
    }

    private var themeGradient: LinearGradient {
        let colors: [Color]
        switch store.dashboardStyle {
        case .softGlass:
            colors = [.white.opacity(0.08), .gray.opacity(0.04)]
        case .sakura:
            colors = [.pink.opacity(0.22), .orange.opacity(0.10), .purple.opacity(0.08)]
        case .mint:
            colors = [.mint.opacity(0.22), .cyan.opacity(0.12), .blue.opacity(0.08)]
        case .midnight:
            colors = [.indigo.opacity(0.62), .purple.opacity(0.40), .black.opacity(0.38)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
