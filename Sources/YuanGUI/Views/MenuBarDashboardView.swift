import AppKit
import SwiftUI

struct MenuBarDashboardView: View {
    @ObservedObject var store: PetStore
    let dashboardHeight: CGFloat
    let togglePet: () -> Void
    let showPet: () -> Void
    let openSettings: () -> Void
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

            WeatherStatusCard(weather: store.weather)
            SystemStatusCard(monitor: store.monitor)

            HStack(spacing: 8) {
                Button("显示/隐藏桌宠", action: togglePet)
                Button(store.showsSystemStatus ? "隐藏迷你状态" : "显示迷你状态") {
                    store.toggleSystemStatus()
                    showPet()
                }
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gearshape.fill")
                }
                .help("设置")
                Menu {
                    Button("元圭与 VCC 清理屋…") { store.showMaintenance() }
                    Divider()
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
        .padding(12)
        .frame(width: 360, height: dashboardHeight)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(themeGradient, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.white.opacity(0.35), lineWidth: 0.8))
        .preferredColorScheme(store.dashboardStyle == .midnight ? .dark : nil)
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
