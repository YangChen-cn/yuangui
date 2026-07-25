import SwiftUI

struct DashboardHeaderView: View {
    @ObservedObject var store: PetStore
    @ObservedObject var focusTimer: FocusTimerStore
    @Binding var showsFocusPopover: Bool
    let showPet: () -> Void

    private var smartState: DashboardSmartStatePresentation {
        .resolve(store.smartState)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: DashboardDesign.compactSpacing) {
                Text("元圭与 VCC")
                    .font(.headline)
                    .bold()
                    .lineLimit(1)
                Spacer(minLength: 8)
                focusButton
            }
            HStack(spacing: 6) {
                Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                DashboardStatusLabel(presentation: smartState)
            }
            .font(.caption)
            HStack(spacing: 5) {
                Image(systemName: weatherIcon)
                    .accessibilityHidden(true)
                Text(weatherSummary)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("面板顶部")
    }

    private var focusButton: some View {
        Button(focusButtonTitle, systemImage: "timer") {
            showsFocusPopover.toggle()
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help(focusTimer.state == .running ? "专注中：\(focusTimer.timeText)" : "打开番茄钟")
        .popover(isPresented: $showsFocusPopover, arrowEdge: .top) {
            FocusTimerControlView(timer: focusTimer, showPet: showPet)
        }
    }

    private var focusButtonTitle: String {
        focusTimer.state == .running ? focusTimer.timeText : "番茄钟"
    }

    private var weatherIcon: String {
        if let snapshot = store.weather.snapshot { return snapshot.condition.symbol }
        if store.weather.status == .locationDenied { return "location.slash" }
        return "cloud"
    }

    private var weatherSummary: String {
        if let snapshot = store.weather.snapshot {
            return "\(store.weather.locationName ?? "当前位置") · \(snapshot.condition.title) \(Int(snapshot.temperature.rounded()))°"
        }
        return switch store.weather.status {
        case .requestingLocation: "正在获取位置"
        case .loading: "正在刷新天气"
        case .locationDenied: "天气定位未授权"
        case .unavailable: "天气暂不可用"
        case .idle, .available: "当前位置天气"
        }
    }
}
