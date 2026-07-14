import Foundation
import XCTest
@testable import YuanGUI

final class WeatherTests: XCTestCase {
    func testWeatherDecoderReadsOpenMeteoCurrentResponse() throws {
        let json = """
        {
          "current": {
            "temperature_2m": 27.4,
            "relative_humidity_2m": 68,
            "apparent_temperature": 30.1,
            "is_day": 1,
            "weather_code": 2,
            "wind_speed_10m": 9.5
          }
        }
        """.data(using: .utf8)!
        let date = Date(timeIntervalSince1970: 123)

        let snapshot = try WeatherDecoder.decode(json, now: date)

        XCTAssertEqual(snapshot.temperature, 27.4)
        XCTAssertEqual(snapshot.apparentTemperature, 30.1)
        XCTAssertEqual(snapshot.relativeHumidity, 68)
        XCTAssertEqual(snapshot.windSpeed, 9.5)
        XCTAssertEqual(snapshot.condition.title, "多云")
        XCTAssertEqual(snapshot.updatedAt, date)
    }

    func testWeatherCodesChooseDayAndNightSymbols() {
        XCTAssertEqual(WeatherCondition.resolve(code: 0, isDay: true).symbol, "sun.max.fill")
        XCTAssertEqual(WeatherCondition.resolve(code: 0, isDay: false).symbol, "moon.stars.fill")
        XCTAssertEqual(WeatherCondition.resolve(code: 95, isDay: true).title, "雷雨")
    }

    func testRainAndBedtimeSmartStates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let rainy = WeatherSnapshot(
            temperature: 20,
            apparentTemperature: 20,
            relativeHumidity: 90,
            windSpeed: 8,
            weatherCode: 63,
            isDay: true,
            updatedAt: Date()
        )
        let noon = calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 12))!
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 2))!

        XCTAssertEqual(
            SmartPetState.resolve(system: .empty, weather: rainy, date: noon, calendar: calendar),
            .rainy
        )
        XCTAssertEqual(
            SmartPetState.resolve(system: .empty, weather: nil, date: lateNight, calendar: calendar),
            .bedtime
        )
    }
}
