import Foundation

struct DashboardWeatherPresentation: Equatable {
    let icon: String
    let primaryText: String
    let conditionText: String
    let detailText: String
    let metadataText: String
    let showsLocationSettings: Bool
    let isRefreshing: Bool

    static func resolve(
        snapshot: WeatherSnapshot?,
        status: WeatherStatus,
        locationName: String?
    ) -> Self {
        if let snapshot {
            return Self(
                icon: snapshot.condition.symbol,
                primaryText: "\(Int(snapshot.temperature.rounded()))°",
                conditionText: "\(snapshot.condition.title) · 体感 \(Int(snapshot.apparentTemperature.rounded()))°",
                detailText: "湿度 \(snapshot.relativeHumidity)% · 风速 \(Int(snapshot.windSpeed.rounded())) km/h",
                metadataText: "\(locationName ?? "当前位置") · \(snapshot.updatedAt.formatted(date: .omitted, time: .shortened)) 更新",
                showsLocationSettings: false,
                isRefreshing: status == .loading || status == .requestingLocation
            )
        }

        let icon: String
        let condition: String
        let detail: String
        switch status {
        case .idle, .available:
            icon = "cloud.sun.fill"
            condition = "当前位置"
            detail = "点击刷新获取本地天气"
        case .requestingLocation:
            icon = "location.fill"
            condition = "正在获取位置"
            detail = "请在系统提示中选择是否允许"
        case .loading:
            icon = "location.fill"
            condition = "正在查询"
            detail = "正在连接天气服务"
        case .locationDenied:
            icon = "location.slash.fill"
            condition = "定位未授权"
            detail = "允许定位后可显示本地天气"
        case .unavailable(let message):
            icon = "cloud.sun.fill"
            condition = "暂不可用"
            detail = message
        }
        return Self(
            icon: icon,
            primaryText: "天气",
            conditionText: condition,
            detailText: detail,
            metadataText: "无需天气 API Key",
            showsLocationSettings: status == .locationDenied,
            isRefreshing: status == .loading || status == .requestingLocation
        )
    }
}
