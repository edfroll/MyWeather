import Foundation

public struct Forecast: Sendable, Equatable {
    /// From response `timezone`; stored at the location (A-22).
    public let timeZone: TimeZone
    /// All 11 metrics.
    public let hourly: HourlyGrid
    /// WMO code per hour, aligned with hourly indices.
    public let weatherCode: [Int?]
    /// Aligned with hourly indices.
    public let isDay: [Bool?]
    /// 16 days.
    public let days: [ForecastDay]

    package init(timeZone: TimeZone, hourly: HourlyGrid, weatherCode: [Int?], isDay: [Bool?], days: [ForecastDay]) {
        self.timeZone = timeZone
        self.hourly = hourly
        self.weatherCode = weatherCode
        self.isDay = isDay
        self.days = days
    }
}

public struct ForecastDay: Sendable, Equatable {
    /// The day `daily.time` labels (D-13), not an instant.
    public let date: LocalDate
    public let weatherCode: Int?
    public let sunrise: Date?
    public let sunset: Date?
    public let temperatureMax: Float?
    public let temperatureMin: Float?

    package init(date: LocalDate, weatherCode: Int?, sunrise: Date?, sunset: Date?,
                 temperatureMax: Float?, temperatureMin: Float?) {
        self.date = date
        self.weatherCode = weatherCode
        self.sunrise = sunrise
        self.sunset = sunset
        self.temperatureMax = temperatureMax
        self.temperatureMin = temperatureMin
    }
}
