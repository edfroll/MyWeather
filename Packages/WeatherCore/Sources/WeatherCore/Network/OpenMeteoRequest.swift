import Foundation

package enum HistorySource: Sendable, Hashable {
    /// Archive API, 9 metrics.
    case archive
    /// Historical Forecast API, uv_index.
    case historicalUV

    /// Latest `end_date` the source accepts (A-22, MW-60):
    /// archive      — min(today in `timeZone`, today in UTC)  (Archive counts "today" in UTC, API §6 п. 9)
    /// historicalUV — today in `timeZone`
    /// The "+1 day" margin at plan edges is fetchPlan's job (A-32), not this function's.
    package func latestEndDate(now: Date, timeZone: TimeZone) -> LocalDate {
        let local = LocalDate(now, in: timeZone)
        switch self {
        case .archive: return min(local, LocalDate(now, in: .gmt))
        case .historicalUV: return local
        }
    }
}

package enum SearchLanguage: String, Sendable { case ru, en }

package struct OpenMeteoRequest: Sendable, Hashable {
    package let url: URL

    private init(url: URL) {
        self.url = url
    }

    package static let forecastHourly: [Metric] = Metric.allCases
    package static let archiveHourly: [Metric] = Metric.allCases.filter { $0 != .precipitationProbability && $0 != .uvIndex }

    package static func forecast(at coordinate: Coordinate) -> OpenMeteoRequest {
        let hourly = (forecastHourly.map(\.apiName) + ["weather_code", "is_day"]).joined(separator: ",")
        return make(host: "api.open-meteo.com", path: "/v1/forecast", items: [
            .init(name: "latitude", value: format(coordinate.latitude)),
            .init(name: "longitude", value: format(coordinate.longitude)),
            .init(name: "forecast_days", value: "16"),
            .init(name: "hourly", value: hourly),
            .init(name: "daily", value: "weather_code,sunrise,sunset,temperature_2m_max,temperature_2m_min"),
        ] + common)
    }

    /// Dates are used as given: clamping to `latestEndDate` is fetchPlan's job (D-4, A-22).
    package static func history(_ source: HistorySource, at coordinate: Coordinate,
                                dates: ClosedRange<LocalDate>) -> OpenMeteoRequest {
        var items: [URLQueryItem] = [
            .init(name: "latitude", value: format(coordinate.latitude)),
            .init(name: "longitude", value: format(coordinate.longitude)),
            .init(name: "start_date", value: dates.lowerBound.iso8601),
            .init(name: "end_date", value: dates.upperBound.iso8601),
        ]
        switch source {
        case .archive:
            items.append(.init(name: "models", value: "ecmwf_ifs"))
            items.append(.init(name: "hourly", value: archiveHourly.map(\.apiName).joined(separator: ",")))
            items.append(.init(name: "daily", value: "sunrise,sunset"))
            return make(host: "archive-api.open-meteo.com", path: "/v1/archive", items: items + common)
        case .historicalUV:
            items.append(.init(name: "hourly", value: Metric.uvIndex.apiName))
            return make(host: "historical-forecast-api.open-meteo.com", path: "/v1/forecast", items: items + common)
        }
    }

    /// Geocoding takes none of the common three parameters (D-10).
    package static func search(name: String, language: SearchLanguage) -> OpenMeteoRequest {
        make(host: "geocoding-api.open-meteo.com", path: "/v1/search", items: [
            .init(name: "name", value: name),
            .init(name: "language", value: language.rawValue),
            .init(name: "count", value: "10"),
        ])
    }

    private static let common: [URLQueryItem] = [
        .init(name: "timezone", value: "auto"),
        .init(name: "wind_speed_unit", value: "ms"),
        .init(name: "timeformat", value: "unixtime"),
    ]

    /// Up to 4 fraction digits, no grouping, POSIX locale (D-11).
    private static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...4)).grouping(.never)
            .locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func make(host: String, path: String, items: [URLQueryItem]) -> OpenMeteoRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = items
        // URLComponents keeps "+" as is, the server reads it as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else {
            preconditionFailure("Open-Meteo URL with a fixed scheme, host and path must build")
        }
        return OpenMeteoRequest(url: url)
    }
}
