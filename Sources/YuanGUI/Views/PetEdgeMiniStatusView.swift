import SwiftUI

struct PetEdgeMiniStatusView: View {
    @ObservedObject private var monitor: SystemMonitor
    let message: String?

    init(store: PetStore, message: String? = nil) {
        _monitor = ObservedObject(wrappedValue: store.monitor)
        self.message = message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            metric("cpu", value: percent(monitor.snapshot.cpu?.total), color: .pink)
            metric("memorychip", value: percent(monitor.snapshot.memory?.fractionUsed), color: .purple)
            metric(
                monitor.snapshot.battery?.isCharging == true ? "bolt.fill" : "battery.75percent",
                value: percent(monitor.snapshot.battery?.chargeFraction),
                color: .mint
            )
            if let message {
                Divider()
                    .opacity(0.45)
                Text(AppLocalizer.string(message))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(
            width: message == nil
                ? PetLayout.edgeStatusSize.width
                : PetLayout.edgeStatusMessageSize.width,
            height: message == nil
                ? PetLayout.edgeStatusSize.height
                : PetLayout.edgeStatusMessageSize.height,
            alignment: .leading
        )
        .yuanLiquidGlassSurface(.clear, cornerRadius: 18)
        .animation(.easeOut(duration: 0.16), value: message)
        .accessibilityHidden(true)
    }

    private func metric(_ icon: String, value: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 13)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }
}
