import SwiftUI

struct PetStatusBubble: View {
    @ObservedObject private var store: PetStore
    @ObservedObject private var monitor: SystemMonitor
    @ObservedObject private var weather: WeatherService

    init(store: PetStore) {
        self.store = store
        self.monitor = store.monitor
        self.weather = store.weather
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: stateIcon)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(stateColor)
                    .symbolEffect(.bounce, value: store.smartState)
                Text(message)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if let value = weather.snapshot {
                    Label("\(Int(value.temperature.rounded()))°", systemImage: value.condition.symbol)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.blue.opacity(0.10), in: Capsule())
                }
            }

            HStack(spacing: 6) {
                metric("CPU", value: cpuText, icon: "cpu", tint: .pink)
                metric("内存", value: memoryText, icon: "memorychip", tint: .purple)
                metric("电量", value: batteryText, icon: batteryIcon, tint: batteryTint)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .frame(width: min(max(PetLayout.baseWidth * store.petScale - 28, 332), 390))
        .background(
            LinearGradient(
                colors: [Color.white.opacity(0.92), Color(red: 0.94, green: 0.97, blue: 1).opacity(0.92), Color.pink.opacity(0.10)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.82), lineWidth: 0.9))
        .shadow(color: stateColor.opacity(0.18), radius: 14, y: 6)
        .overlay(alignment: .bottom) {
            BubbleTail()
                .fill(.regularMaterial)
                .frame(width: 20, height: 10)
                .offset(y: 8)
        }
    }

    private func metric(_ title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(title) \(value)")
        }
        .font(.system(size: 11.5, weight: .bold, design: .rounded))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.68), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.16), lineWidth: 0.7))
    }

    private var message: String {
        if let taskMessage = store.taskMessage { return taskMessage }
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

private struct BubbleTail: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.midX, y: rect.maxY)
            )
            path.closeSubpath()
        }
    }
}
