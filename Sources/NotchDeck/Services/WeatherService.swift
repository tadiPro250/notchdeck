import Combine
import Foundation

struct Weather: Equatable {
    var city: String
    var temperature: Double
    var high: Double
    var low: Double
    var code: Int
    var isDay: Bool
    var unit: TemperatureUnit

    var symbol: String { WeatherService.symbol(code: code, isDay: isDay) }
    var summary: String { WeatherService.summary(code: code) }
}

/// Current conditions from Open-Meteo (free, no API key), for the city set in Settings.
final class WeatherService: ObservableObject {
    @Published private(set) var weather: Weather?
    @Published private(set) var problem: String?

    private let settings: AppSettings
    private var timer: Timer?
    private var bag = Set<AnyCancellable>()
    private var place: (query: String, latitude: Double, longitude: Double, name: String)?

    init(settings: AppSettings, live: Bool = true) {
        self.settings = settings
        guard live else { return }
        settings.$weatherCity.combineLatest(settings.$temperatureUnit)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &bag)
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func showPreview(_ weather: Weather) {
        self.weather = weather
    }

    func refresh() {
        let city = settings.weatherCity.trimmingCharacters(in: .whitespaces)
        let unit = settings.temperatureUnit
        guard !city.isEmpty else {
            weather = nil
            problem = "Set your city in Settings → Weather"
            return
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                let place = try await self.locate(city)
                let weather = try await Self.forecast(place: place, unit: unit)
                await MainActor.run {
                    self.weather = weather
                    self.problem = nil
                }
            } catch {
                await MainActor.run { self.problem = "Couldn't load weather for \(city)" }
            }
        }
    }

    private func locate(_ city: String) async throws -> (query: String, latitude: Double, longitude: Double, name: String) {
        if let place, place.query == city { return place }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1")]
        struct Response: Decodable {
            struct Result: Decodable { let name: String; let latitude: Double; let longitude: Double }
            let results: [Result]?
        }
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        guard let first = try JSONDecoder().decode(Response.self, from: data).results?.first else {
            throw URLError(.cannotFindHost)
        }
        let found = (query: city, latitude: first.latitude, longitude: first.longitude, name: first.name)
        await MainActor.run { self.place = found }
        return found
    }

    private static func forecast(place: (query: String, latitude: Double, longitude: Double, name: String),
                                 unit: TemperatureUnit) async throws -> Weather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(place.latitude)),
            URLQueryItem(name: "longitude", value: String(place.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: unit.rawValue),
        ]
        struct Response: Decodable {
            struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
            struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
            let current: Current
            let daily: Daily
        }
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let r = try JSONDecoder().decode(Response.self, from: data)
        return Weather(city: place.name, temperature: r.current.temperature_2m,
                       high: r.daily.temperature_2m_max.first ?? r.current.temperature_2m,
                       low: r.daily.temperature_2m_min.first ?? r.current.temperature_2m,
                       code: r.current.weather_code, isDay: r.current.is_day == 1, unit: unit)
    }

    /// WMO weather interpretation codes → SF Symbols.
    static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func summary(code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95...99: return "Thunderstorm"
        default: return "—"
        }
    }
}
