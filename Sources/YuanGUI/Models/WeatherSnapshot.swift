import Foundation

struct WeatherSnapshot: Equatable {
    let temperature: Double
    let apparentTemperature: Double
    let relativeHumidity: Int
    let windSpeed: Double
    let weatherCode: Int
    let isDay: Bool
    let updatedAt: Date

    var condition: WeatherCondition {
        WeatherCondition.resolve(code: weatherCode, isDay: isDay)
    }

    var isRainy: Bool {
        switch weatherCode {
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82, 95, 96, 99:
            return true
        default:
            return false
        }
    }
}

struct WeatherCondition: Equatable {
    let title: String
    let symbol: String

    static func resolve(code: Int, isDay: Bool) -> WeatherCondition {
        switch code {
        case 0: return WeatherCondition(title: "晴朗", symbol: isDay ? "sun.max.fill" : "moon.stars.fill")
        case 1: return WeatherCondition(title: "大致晴朗", symbol: isDay ? "sun.min.fill" : "moon.fill")
        case 2: return WeatherCondition(title: "多云", symbol: isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3: return WeatherCondition(title: "阴天", symbol: "cloud.fill")
        case 45, 48: return WeatherCondition(title: "有雾", symbol: "cloud.fog.fill")
        case 51, 53, 55, 56, 57: return WeatherCondition(title: "毛毛雨", symbol: "cloud.drizzle.fill")
        case 61, 63, 65, 66, 67, 80, 81, 82: return WeatherCondition(title: "下雨", symbol: "cloud.rain.fill")
        case 71, 73, 75, 77, 85, 86: return WeatherCondition(title: "下雪", symbol: "cloud.snow.fill")
        case 95, 96, 99: return WeatherCondition(title: "雷雨", symbol: "cloud.bolt.rain.fill")
        default: return WeatherCondition(title: "天气变化中", symbol: "cloud.fill")
        }
    }
}

enum WeatherStatus: Equatable {
    case idle
    case requestingLocation
    case loading
    case available
    case locationDenied
    case unavailable(String)
}
