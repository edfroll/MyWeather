import Foundation

package struct ArchiveData: Sendable, Equatable {
    /// 9 metrics: Metric.allCases without precipitationProbability, uvIndex.
    package let hourly: HourlyGrid
    package let days: [SunDay]

    package init(hourly: HourlyGrid, days: [SunDay]) {
        self.hourly = hourly
        self.days = days
    }
}

package struct SunDay: Sendable, Equatable {
    /// D-13.
    package let date: LocalDate
    package let sunrise: Date?
    package let sunset: Date?

    package init(date: LocalDate, sunrise: Date?, sunset: Date?) {
        self.date = date
        self.sunrise = sunrise
        self.sunset = sunset
    }
}
