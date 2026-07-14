import Foundation
import XCTest
import CoreLocation
@testable import YuanGUI

final class WeatherTests: XCTestCase {
    func testManualWeatherRefreshRequestBypassesCaches() throws {
        let location = CLLocation(latitude: 31.2304, longitude: 121.4737)
        let request = try XCTUnwrap(WeatherService.weatherRequest(for: location, forceReload: true))
        XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
        XCTAssertEqual(request.timeoutInterval, 15)
        XCTAssertTrue(try XCTUnwrap(request.url?.absoluteString).contains("latitude=31.2304"))
        XCTAssertTrue(try XCTUnwrap(request.url?.absoluteString).contains("longitude=121.4737"))
    }

    func testAutomaticWeatherRequestUsesNormalCachePolicy() throws {
        let location = CLLocation(latitude: 22.5431, longitude: 114.0579)
        let request = try XCTUnwrap(WeatherService.weatherRequest(for: location, forceReload: false))
        XCTAssertEqual(request.cachePolicy, .useProtocolCachePolicy)
        XCTAssertEqual(WeatherService.refreshInterval, 15 * 60)
    }

    @MainActor
    func testManualRefreshShowsLoadingAndStoresFreshWeather() async throws {
        let json = """
        {
          "current": {
            "temperature_2m": 18.5,
            "relative_humidity_2m": 72,
            "apparent_temperature": 17.8,
            "is_day": 1,
            "weather_code": 1,
            "wind_speed_10m": 4.2
          }
        }
        """.data(using: .utf8)!
        let location = CLLocation(latitude: 30.5728, longitude: 104.0668)
        let service = WeatherService(initialLocation: location) { request in
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalAndRemoteCacheData)
            await Task.yield()
            return (
                json,
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!
            )
        }

        service.refresh()
        XCTAssertEqual(service.status, .loading)

        for _ in 0..<20 where service.status != .available {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertEqual(service.status, .available)
        XCTAssertEqual(service.snapshot?.temperature, 18.5)
        XCTAssertEqual(service.snapshot?.condition.title, "大致晴朗")
    }

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
        let elevenPM = calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 23))!
        let fiveAM = calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 5))!

        XCTAssertEqual(
            SmartPetState.resolve(system: .empty, weather: rainy, date: noon, calendar: calendar),
            .rainy
        )
        XCTAssertEqual(
            SmartPetState.resolve(system: .empty, weather: nil, date: lateNight, calendar: calendar),
            .bedtime
        )
        XCTAssertEqual(SmartPetState.resolve(system: .empty, weather: nil, date: elevenPM, calendar: calendar), .bedtime)
        XCTAssertEqual(SmartPetState.resolve(system: .empty, weather: nil, date: fiveAM, calendar: calendar), .normal)
    }

    func testMultipleSmartStatesAreKeptForRotation() {
        var snapshot = SystemSnapshot.empty
        snapshot.battery = BatteryMetrics(
            isPresent: true,
            chargeFraction: 0.8,
            isCharging: true,
            powerSource: .ac,
            timeRemainingMinutes: 20
        )
        let rainy = WeatherSnapshot(
            temperature: 18,
            apparentTemperature: 17,
            relativeHumidity: 90,
            windSpeed: 8,
            weatherCode: 61,
            isDay: true,
            updatedAt: Date()
        )
        let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 12))!

        XCTAssertEqual(
            SmartPetState.resolveAll(system: snapshot, weather: rainy, date: noon),
            [.rainy, .charging]
        )
    }

    func testBedtimeScheduleCanBeCustomizedOrDisabled() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let atEleven = calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 23, minute: 30))!
        let atTwo = calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 2))!

        XCTAssertTrue(SmartPetState.resolveAll(
            system: .empty, weather: nil, date: atEleven, calendar: calendar,
            bedtimeEnabled: true, bedtimeStartMinutes: 22 * 60, bedtimeEndMinutes: 60
        ).contains(.bedtime))
        XCTAssertFalse(SmartPetState.resolveAll(
            system: .empty, weather: nil, date: atTwo, calendar: calendar,
            bedtimeEnabled: true, bedtimeStartMinutes: 22 * 60, bedtimeEndMinutes: 60
        ).contains(.bedtime))
        XCTAssertFalse(SmartPetState.resolveAll(
            system: .empty, weather: nil, date: atEleven, calendar: calendar,
            bedtimeEnabled: false, bedtimeStartMinutes: 22 * 60, bedtimeEndMinutes: 60
        ).contains(.bedtime))
    }
}
