import SwiftUI

struct DiaryMetadataSection: View {
    let weather: DiaryWeatherSnapshot?
    let music: DiaryMusicSnapshot?
    @Binding var locationName: String
    let onUseCurrentLocation: () async -> String?

    @State private var isLocating = false
    @State private var locationError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DiarySectionLabel(title: "那一刻", systemImage: "sparkles")
            VStack(alignment: .leading, spacing: 9) {
                if let weather, !weather.condition.isEmpty {
                    metadataRow(
                        icon: weather.icon,
                        text: "\(Int(weather.temperature))°C  \(weather.condition)"
                    )
                }
                if let music, !music.title.isEmpty {
                    metadataRow(
                        icon: "music.note",
                        text: "正在听《\(music.title)》— \(music.artist)"
                    )
                }
                HStack(spacing: 9) {
                    Image(systemName: "mappin.and.ellipse")
                        .frame(width: 16)
                        .foregroundStyle(.secondary)
                    TextField("记录地点", text: $locationName)
                        .textFieldStyle(.plain)
                    Button { useCurrentLocation() } label: {
                        if isLocating {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "location.fill")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isLocating)
                    .help("使用当前位置")
                    .accessibilityLabel("使用当前位置")
                }
                if let locationError {
                    Label(locationError, systemImage: "location.slash")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.diarySecondarySurface, in: RoundedRectangle(cornerRadius: DiaryDesign.cardCornerRadius))
        }
    }

    private func metadataRow(icon: String, text: String) -> some View {
        Label {
            Text(text).lineLimit(2)
        } icon: {
            Image(systemName: icon)
                .frame(width: 16)
        }
        .foregroundStyle(.secondary)
    }

    private func useCurrentLocation() {
        isLocating = true
        locationError = nil
        Task {
            if let resolved = await onUseCurrentLocation() {
                locationName = resolved
            } else {
                locationError = "无法获取当前位置"
            }
            isLocating = false
        }
    }
}
