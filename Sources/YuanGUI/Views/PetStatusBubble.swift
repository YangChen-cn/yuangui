import SwiftUI

struct PetStatusBubble: View {
    @ObservedObject private var store: PetStore
    @ObservedObject private var monitor: SystemMonitor
    @ObservedObject private var weather: WeatherService
    let placement: PetAuxiliaryBubblePlacement

    init(store: PetStore, placement: PetAuxiliaryBubblePlacement = .abovePet) {
        self.store = store
        self.monitor = store.monitor
        self.weather = store.weather
        self.placement = placement
    }

    var body: some View {
        VStack(spacing: 8 * visualScale) {
            HStack(spacing: 8 * visualScale) {
                Image(systemName: stateIcon)
                    .font(.system(size: 19 * visualScale, weight: .bold))
                    .foregroundStyle(stateColor)
                    .symbolEffect(.bounce, value: store.smartState)
                Text(AppLocalizer.string(message))
                    .font(.system(size: max(10, 12 * visualScale), weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if let value = weather.snapshot {
                    HStack(spacing: 4 * visualScale) {
                        Image(systemName: value.condition.symbol)
                        Text("\(Int(value.temperature.rounded()))°")
                            .lineLimit(1)
                    }
                        .font(.system(size: max(9, 10 * visualScale), weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7 * visualScale)
                        .padding(.vertical, 4 * visualScale)
                        .background(.blue.opacity(0.10), in: Capsule())
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(2)
                }
            }

            HStack(spacing: 6 * visualScale) {
                metric(AppLocalizer.string("CPU"), value: cpuText, icon: "cpu", tint: .pink)
                metric(AppLocalizer.string("内存"), value: memoryText, icon: "memorychip", tint: .purple)
                metric(AppLocalizer.string("电量"), value: batteryText, icon: batteryIcon, tint: batteryTint)
            }
        }
        .padding(.horizontal, 13 * visualScale)
        .padding(.vertical, 11 * visualScale)
        .frame(width: PetLayout.statusBubbleWidth(scale: store.petScale))
        .yuanPetBubbleGlass(
            cornerRadius: 20 * visualScale,
            placement: placement,
            tailWidth: 20 * visualScale,
            tailHeight: 10 * visualScale,
            tailOffset: 8 * visualScale
        )
    }

    private func metric(_ title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 4 * visualScale) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(store.petScale < 0.70 ? value : "\(title) \(value)")
                .foregroundStyle(.primary)
        }
        .font(.system(size: max(9.5, 11.5 * visualScale), weight: .bold, design: .rounded))
        .padding(.horizontal, 9 * visualScale)
        .padding(.vertical, 6 * visualScale)
        .background(tint.opacity(0.10), in: Capsule())
    }

    private var visualScale: CGFloat {
        PetLayout.compactBubbleScale(scale: store.petScale)
    }

    private var message: String {
        if let taskMessage = store.taskMessage { return taskMessage }
        if let ambientMessage = store.ambientMessage { return ambientMessage }
        return PetStatusMessageResolver.message(
            snapshot: monitor.snapshot,
            smartState: store.smartState
        )
    }

    private var stateIcon: String {
        switch store.smartState {
        case .normal: return "heart.fill"
        case .lowBattery: return "battery.25percent"
        case .memoryPressure: return "exclamationmark.bubble.fill"
        case .charging: return "bolt.heart.fill"
        case .rainy: return "umbrella.fill"
        case .bedtime: return "moon.zzz.fill"
        }
    }

    private var stateColor: Color {
        switch store.smartState {
        case .normal: return .pink
        case .lowBattery: return .orange
        case .memoryPressure: return .red
        case .charging: return .mint
        case .rainy: return .blue
        case .bedtime: return .indigo
        }
    }

    private var cpuText: String { monitor.snapshot.cpu.map { MetricFormatting.percent($0.total) } ?? "--" }
    private var memoryText: String { monitor.snapshot.memory.map { MetricFormatting.percent($0.fractionUsed) } ?? "--" }
    private var batteryText: String {
        guard let battery = monitor.snapshot.battery else { return "--" }
        guard battery.isPresent else { return "AC" }
        return battery.chargeFraction.map(MetricFormatting.percent) ?? "--"
    }
    private var batteryIcon: String { monitor.snapshot.battery?.isCharging == true ? "bolt.fill" : "battery.75percent" }
    private var batteryTint: Color {
        (monitor.snapshot.battery?.chargeFraction ?? 1) <= 0.2 ? .orange : .mint
    }
}
