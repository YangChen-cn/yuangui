import SwiftUI

/// 天气快照卡片
struct WeatherCardView: View {
    let weather: DiaryWeatherSnapshot?

    var body: some View {
        if let weather, !weather.condition.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: weather.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("\(Int(weather.temperature))°C")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                Text(weather.condition)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.blue.opacity(0.08), in: Capsule())
        }
    }
}
