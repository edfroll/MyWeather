import Foundation

/// One shape for all responses (D-9); never leaves this file.
private struct ResponseDTO: Decodable {
    let timezone: String?
    let utc_offset_seconds: Int?
    let hourly: [String: [Double?]]?
    let daily: [String: [Double?]]?
}

package enum OpenMeteoDecoding {
    package static func decodeForecast(_ data: Data) throws(WeatherError) -> Forecast {
        let dto = try decode(data)
        let timeZone = try timeZone(of: dto)
        let hourly = try hourlyColumns(of: dto, expected: OpenMeteoRequest.forecastHourly.map(\.apiName)
            + ["weather_code", "is_day"])
        let grid = try makeGrid(hourly, metrics: OpenMeteoRequest.forecastHourly)
        let codes = try hourly.columns["weather_code"].unwrapped().map { value throws(WeatherError) -> Int? in
            guard let value else { return nil }
            guard let code = Int(exactly: value) else { throw .decoding }
            return code
        }
        let isDay = try hourly.columns["is_day"].unwrapped().map { value throws(WeatherError) -> Bool? in
            guard let value else { return nil }
            switch value {
            case 0: return false
            case 1: return true
            default: throw .decoding
            }
        }
        let daily = try dailyColumns(of: dto, expected: ["weather_code", "sunrise", "sunset",
                                                          "temperature_2m_max", "temperature_2m_min"])
        var days: [ForecastDay] = []
        for index in 0..<daily.time.count {
            var code: Int?
            if let raw = try daily.columns["weather_code"].unwrapped()[index] {
                guard let exact = Int(exactly: raw) else { throw .decoding }
                code = exact
            }
            days.append(ForecastDay(
                date: daily.time[index],
                weatherCode: code,
                sunrise: instant(try daily.columns["sunrise"].unwrapped()[index]),
                sunset: instant(try daily.columns["sunset"].unwrapped()[index]),
                temperatureMax: try daily.columns["temperature_2m_max"].unwrapped()[index].map(Float.init),
                temperatureMin: try daily.columns["temperature_2m_min"].unwrapped()[index].map(Float.init)))
        }
        return Forecast(timeZone: timeZone, hourly: grid, weatherCode: codes, isDay: isDay, days: days)
    }

    package static func decodeArchive(_ data: Data) throws(WeatherError) -> ArchiveData {
        let dto = try decode(data)
        _ = try timeZone(of: dto)
        let metrics = OpenMeteoRequest.archiveHourly
        let hourly = try hourlyColumns(of: dto, expected: metrics.map(\.apiName))
        let grid = try makeGrid(hourly, metrics: metrics)
        let daily = try dailyColumns(of: dto, expected: ["sunrise", "sunset"])
        var days: [SunDay] = []
        for index in 0..<daily.time.count {
            days.append(SunDay(
                date: daily.time[index],
                sunrise: instant(try daily.columns["sunrise"].unwrapped()[index]),
                sunset: instant(try daily.columns["sunset"].unwrapped()[index])))
        }
        return ArchiveData(hourly: grid, days: days)
    }

    package static func decodeHistoricalUV(_ data: Data) throws(WeatherError) -> HourlyGrid {
        let dto = try decode(data)
        _ = try timeZone(of: dto)
        let hourly = try hourlyColumns(of: dto, expected: [Metric.uvIndex.apiName])
        return try makeGrid(hourly, metrics: [.uvIndex])
    }

    @concurrent package static func forecast(from data: Data) async throws(WeatherError) -> Forecast {
        try decodeForecast(data)
    }

    @concurrent package static func archive(from data: Data) async throws(WeatherError) -> ArchiveData {
        try decodeArchive(data)
    }

    @concurrent package static func historicalUV(from data: Data) async throws(WeatherError) -> HourlyGrid {
        try decodeHistoricalUV(data)
    }

    // MARK: - Shared rules

    private struct Hourly {
        let time: [Double]
        let columns: [String: [Double?]]
    }

    private struct Daily {
        let time: [LocalDate]
        let columns: [String: [Double?]]
    }

    private static func decode(_ data: Data) throws(WeatherError) -> ResponseDTO {
        do {
            return try JSONDecoder().decode(ResponseDTO.self, from: data)
        } catch {
            throw .decoding
        }
    }

    private static func timeZone(of dto: ResponseDTO) throws(WeatherError) -> TimeZone {
        guard let identifier = dto.timezone, let zone = TimeZone(identifier: identifier) else { throw .decoding }
        return zone
    }

    private static func hourlyColumns(of dto: ResponseDTO, expected: [String]) throws(WeatherError) -> Hourly {
        guard let hourly = dto.hourly, let rawTime = hourly["time"] else { throw .decoding }
        guard !rawTime.isEmpty else { throw .noData }
        var time: [Double] = []
        for value in rawTime {
            guard let value else { throw .decoding }
            time.append(value)
        }
        for (previous, next) in zip(time, time.dropFirst()) where next - previous != HourlyGrid.step {
            throw .decoding
        }
        var columns: [String: [Double?]] = [:]
        for name in expected {
            guard let column = hourly[name], column.count == time.count else { throw .decoding }
            columns[name] = column
        }
        return Hourly(time: time, columns: columns)
    }

    private static func makeGrid(_ hourly: Hourly, metrics: [Metric]) throws(WeatherError) -> HourlyGrid {
        var values: [Metric: [Float]] = [:]
        for metric in metrics {
            guard let column = hourly.columns[metric.apiName] else { throw .decoding }
            values[metric] = column.map { $0.map(Float.init) ?? .nan }
        }
        return try HourlyGrid(start: Date(timeIntervalSince1970: hourly.time[0]), count: hourly.time.count,
                              values: values)
    }

    private static func dailyColumns(of dto: ResponseDTO, expected: [String]) throws(WeatherError) -> Daily {
        guard let daily = dto.daily, let rawTime = daily["time"] else { throw .decoding }
        var time: [LocalDate] = []
        if !rawTime.isEmpty {
            guard let offset = dto.utc_offset_seconds else { throw .decoding }
            for value in rawTime {
                guard let value else { throw .decoding }
                time.append(LocalDate(Date(timeIntervalSince1970: value + Double(offset)), in: .gmt))
            }
        }
        var columns: [String: [Double?]] = [:]
        for name in expected {
            guard let column = daily[name], column.count == rawTime.count else { throw .decoding }
            columns[name] = column
        }
        return Daily(time: time, columns: columns)
    }

    private static func instant(_ value: Double?) -> Date? {
        value.map { Date(timeIntervalSince1970: $0) }
    }
}

private extension Optional {
    func unwrapped() throws(WeatherError) -> Wrapped {
        guard let self else { throw .decoding }
        return self
    }
}
