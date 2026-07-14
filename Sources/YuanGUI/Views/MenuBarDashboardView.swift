import AppKit
import SwiftUI

struct MenuBarDashboardView: View {
    @ObservedObject var store: PetStore
    let dashboardHeight: CGFloat
    let togglePet: () -> Void
    let showPet: () -> Void
    let dismiss: () -> Void

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
                Label(smartStateTitle, systemImage: smartStateIcon)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(smartStateColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(smartStateColor.opacity(0.10), in: Capsule())
            }
            .padding(.horizontal, 4)

            ScrollView {
                VStack(spacing: 10) {
                    WeatherStatusCard(weather: store.weather)
                    SystemStatusCard(monitor: store.monitor)

                    VStack(spacing: 10) {
                        Picker("角色", selection: Binding(
                            get: { store.mode },
                            set: { store.setMode($0); showPet() }
                        )) {
                            ForEach(PetMode.allCases) { mode in Text(mode.title).tag(mode) }
                        }
                        .pickerStyle(.segmented)

                        HStack(spacing: 9) {
                            Label("大小", systemImage: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Button { store.adjustPetScale(by: -0.05) } label: { Image(systemName: "minus") }
                                .buttonStyle(.borderless)
                            Slider(
                                value: Binding(get: { store.petScale }, set: store.setPetScale),
                                in: PetLayout.minimumScale...PetLayout.maximumScale,
                                step: 0.05
                            )
                            Button { store.adjustPetScale(by: 0.05) } label: { Image(systemName: "plus") }
                                .buttonStyle(.borderless)
                            Text("\(Int((store.petScale * 100).rounded()))%")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .frame(width: 38, alignment: .trailing)
                        }

                        Toggle(isOn: Binding(
                            get: { store.smartReactionsEnabled },
                            set: store.setSmartReactionsEnabled
                        )) {
                            Label("根据系统、天气和时间智能改变动作", systemImage: "sparkles")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.visible)

            HStack(spacing: 8) {
                Button("显示/隐藏桌宠", action: togglePet)
                Button(store.showsSystemStatus ? "隐藏迷你状态" : "显示迷你状态") {
                    store.toggleSystemStatus()
                    showPet()
                }
                Spacer()
                Menu {
                    Button("打开废纸篓") { store.openTrash() }
                    Button("清空废纸篓…") { store.confirmAndEmptyTrash() }
                    Divider()
                    Button("退出") { NSApp.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 388, height: dashboardHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.35), lineWidth: 0.8))
        .onAppear {
            store.monitor.refresh()
        }
        .onExitCommand(perform: dismiss)
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
}
