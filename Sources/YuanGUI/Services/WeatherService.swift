@preconcurrency import CoreLocation
import Foundation

@MainActor
final class WeatherService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    nonisolated static let refreshInterval: TimeInterval = 15 * 60
    nonisolated static let retryInterval: TimeInterval = 5 * 60

    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var status: WeatherStatus = .idle

    private let locationManager: CLLocationManager
    private let loadData: DataLoader
    private var lastLocation: CLLocation?
    private var lastFetchDate: Date?
    private var isStarted = false
    private var fetchTask: Task<Void, Never>?
    private var scheduledRefreshTask: Task<Void, Never>?

    init(
        session: URLSession = .shared,
        initialLocation: CLLocation? = nil,
        dataLoader: DataLoader? = nil
    ) {
        self.loadData = dataLoader ?? { request in
            try await session.data(for: request)
        }
        self.locationManager = CLLocationManager()
        self.lastLocation = initialLocation
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager.distanceFilter = 10_000
    }

    func start() {
        guard !isStarted else {
            refreshIfNeeded()
            return
        }
        isStarted = true
        handleAuthorization(locationManager.authorizationStatus)
    }

    func refresh() {
        if let lastLocation {
            fetchWeather(at: lastLocation, forceReload: true)
        } else {
            start()
            requestLocationIfAuthorized(showLoading: true)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard isStarted else { return }
        handleAuthorization(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        lastLocation = location
        fetchWeather(at: location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let locationError = error as? CLError, locationError.code == .denied {
            status = .locationDenied
        } else {
            status = .unavailable("暂时无法获取位置")
        }
        scheduleNextRefresh(after: Self.retryInterval)
    }

    private func handleAuthorization(_ authorization: CLAuthorizationStatus) {
        switch authorization {
        case .notDetermined:
            status = .requestingLocation
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways:
            requestLocationIfAuthorized()
        case .denied, .restricted:
            status = .locationDenied
        @unknown default:
            status = .unavailable("定位状态不可用")
        }
    }

    private func requestLocationIfAuthorized(showLoading: Bool = false) {
        let authorization = locationManager.authorizationStatus
        guard authorization == .authorizedAlways else { return }
        status = (snapshot == nil || showLoading) ? .requestingLocation : .available
        locationManager.requestLocation()
    }

    private func refreshIfNeeded() {
        guard let lastFetchDate else {
            requestLocationIfAuthorized()
            return
        }
        let elapsed = Date().timeIntervalSince(lastFetchDate)
        if elapsed >= Self.refreshInterval {
            requestLocationIfAuthorized()
        } else {
            scheduleNextRefresh(after: Self.refreshInterval - elapsed)
        }
    }

    private func fetchWeather(at location: CLLocation, forceReload: Bool = false) {
        status = (snapshot == nil || forceReload) ? .loading : .available
        guard let request = Self.weatherRequest(for: location, forceReload: forceReload) else {
            status = .unavailable("天气请求地址无效")
            scheduleNextRefresh(after: Self.retryInterval)
            return
        }

        fetchTask?.cancel()
        fetchTask = Task {
            do {
                let (data, response) = try await loadData(request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let value = try WeatherDecoder.decode(data)
                snapshot = value
                lastFetchDate = value.updatedAt
                status = .available
                scheduleNextRefresh(after: Self.refreshInterval)
            } catch is CancellationError {
                return
            } catch {
                status = .unavailable("天气服务暂时不可用")
                scheduleNextRefresh(after: Self.retryInterval)
            }
        }
    }

    nonisolated static func weatherRequest(for location: CLLocation, forceReload: Bool) -> URLRequest? {
        let latitude = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), location.coordinate.latitude)
        let longitude = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), location.coordinate.longitude)
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: latitude),
            URLQueryItem(name: "longitude", value: longitude),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = forceReload ? .reloadIgnoringLocalAndRemoteCacheData : .useProtocolCachePolicy
        request.timeoutInterval = 15
        return request
    }

    private func scheduleNextRefresh(after delay: TimeInterval) {
        scheduledRefreshTask?.cancel()
        scheduledRefreshTask = Task { @MainActor [weak self] in
            let nanoseconds = UInt64(max(1, delay) * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled, let self else { return }
            self.requestLocationIfAuthorized()
        }
    }
}

enum WeatherDecoder {
    static func decode(_ data: Data, now: Date = Date()) throws -> WeatherSnapshot {
        let response = try JSONDecoder().decode(WeatherAPIResponse.self, from: data)
        return WeatherSnapshot(
            temperature: response.current.temperature2m,
            apparentTemperature: response.current.apparentTemperature,
            relativeHumidity: response.current.relativeHumidity2m,
            windSpeed: response.current.windSpeed10m,
            weatherCode: response.current.weatherCode,
            isDay: response.current.isDay == 1,
            updatedAt: now
        )
    }
}

private struct WeatherAPIResponse: Decodable {
    struct Current: Decodable {
        let temperature2m: Double
        let relativeHumidity2m: Int
        let apparentTemperature: Double
        let isDay: Int
        let weatherCode: Int
        let windSpeed10m: Double

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case relativeHumidity2m = "relative_humidity_2m"
            case apparentTemperature = "apparent_temperature"
            case isDay = "is_day"
            case weatherCode = "weather_code"
            case windSpeed10m = "wind_speed_10m"
        }
    }

    let current: Current

}
