import Foundation
import Testing
import WeatherCore

struct OpenMeteoDecodingTests {
    private func localIndices(_ grid: HourlyGrid, zone: TimeZone, day: LocalDate) -> Int {
        (0..<grid.count).filter { LocalDate(grid.date(at: $0), in: zone) == day }.count
    }

    @Test func forecastMumbai() throws {
        let forecast = try OpenMeteoDecoding.decodeForecast(Fixture.data("forecast-mumbai"))
        #expect(forecast.timeZone.identifier == "Asia/Kolkata")
        #expect(forecast.hourly.start.timeIntervalSince1970 == 1_794_421_800)
        #expect(Int(forecast.hourly.start.timeIntervalSince1970) % 3600 == 1800)
        #expect(forecast.hourly.count == 384)
        #expect(forecast.hourly.metrics == Set(Metric.allCases))
        #expect(forecast.weatherCode.count == 384)
        #expect(forecast.isDay.count == 384)
        #expect(forecast.days.count == 16)
        #expect(forecast.days[0].date == LocalDate(year: 2026, month: 11, day: 12))
    }

    @Test func forecastAucklandTail() throws {
        let forecast = try OpenMeteoDecoding.decodeForecast(Fixture.data("forecast-auckland"))
        #expect(forecast.hourly.value(.temperature, at: 380) == nil)
        #expect(forecast.hourly.value(.temperature, at: 379) != nil)
        #expect(forecast.days[15].weatherCode == nil)
    }

    @Test func forecastBerlinTail() throws {
        let forecast = try OpenMeteoDecoding.decodeForecast(Fixture.data("forecast-berlin"))
        #expect(forecast.hourly.value(.precipitationProbability, at: 364) == nil)
        #expect(forecast.hourly.value(.temperature, at: 364) != nil)
    }

    @Test func daylightSavingBerlin() throws {
        let archive = try OpenMeteoDecoding.decodeArchive(Fixture.data("archive-berlin-year"))
        let zone = try #require(TimeZone(identifier: "Europe/Berlin"))
        #expect(archive.hourly.count == 8760)
        #expect(localIndices(archive.hourly, zone: zone, day: LocalDate(year: 2025, month: 3, day: 30)) == 23)
        #expect(localIndices(archive.hourly, zone: zone, day: LocalDate(year: 2025, month: 10, day: 26)) == 25)
        let expected = Set(Metric.allCases).subtracting([.uvIndex, .precipitationProbability])
        #expect(archive.hourly.metrics == expected)
        #expect(archive.days.count == 365)
        #expect(archive.days[89].date == LocalDate(year: 2025, month: 3, day: 31))
        #expect(archive.days[298].date == LocalDate(year: 2025, month: 10, day: 26))
    }

    @Test func daylightSavingNewYork() throws {
        let archive = try OpenMeteoDecoding.decodeArchive(Fixture.data("archive-newyork-dst"))
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        #expect(localIndices(archive.hourly, zone: zone, day: LocalDate(year: 2025, month: 11, day: 2)) == 25)
        #expect(archive.hourly.metrics.count == 9)
        #expect(archive.days[3].date == LocalDate(year: 2025, month: 11, day: 2))
    }

    @Test func historicalUV() throws {
        let grid = try OpenMeteoDecoding.decodeHistoricalUV(Fixture.data("historical-forecast-auckland-end-today"))
        #expect(grid.metrics == [.uvIndex])
        #expect(grid.count == 216)
    }

    @Test func murmanskPolarDay() throws {
        let archive = try OpenMeteoDecoding.decodeArchive(Fixture.data("archive-murmansk-june"))
        #expect(archive.days.count == 30)
        for day in archive.days {
            let sunrise = try #require(day.sunrise)
            let sunset = try #require(day.sunset)
            #expect(sunset.timeIntervalSince(sunrise) == 86400)
        }
    }

    // MARK: - Synthetic bodies

    private func uvBody(time: String = "[0,3600]", uv: String = "[1,2]", tz: String = "\"UTC\"") -> Data {
        Data("{\"timezone\":\(tz),\"utc_offset_seconds\":0,\"hourly\":{\"time\":\(time),\"uv_index\":\(uv)}}".utf8)
    }

    private func forecastBody(is_day: String = "[1,0]", daily: String? = nil) -> Data {
        var columns = Metric.allCases.map { "\"\($0.apiName)\":[1,2]" }
        columns.append("\"weather_code\":[1,2]")
        columns.append("\"is_day\":\(is_day)")
        var body = "{\"timezone\":\"UTC\",\"utc_offset_seconds\":0,\"hourly\":{\"time\":[0,3600],\(columns.joined(separator: ","))}"
        if let daily { body += ",\"daily\":\(daily)" }
        body += "}"
        return Data(body.utf8)
    }

    private let dailyOK = """
        {"time":[0],"weather_code":[1],"sunrise":[100],"sunset":[200],"temperature_2m_max":[1],"temperature_2m_min":[0]}
        """

    @Test func syntheticValid() throws {
        let grid = try OpenMeteoDecoding.decodeHistoricalUV(uvBody())
        #expect(grid.count == 2)
        #expect(grid.value(.uvIndex, at: 1) == 2)
    }

    @Test func syntheticBrokenBodies() {
        #expect(throws: WeatherError.decoding) { try OpenMeteoDecoding.decodeHistoricalUV(uvBody(time: "[0,1800]")) }
        #expect(throws: WeatherError.decoding) { try OpenMeteoDecoding.decodeHistoricalUV(uvBody(uv: "[1]")) }
        #expect(throws: WeatherError.decoding) {
            try OpenMeteoDecoding.decodeHistoricalUV(Data(#"{"timezone":"UTC","hourly":{"time":[0]}}"#.utf8))
        }
        #expect(throws: WeatherError.noData) { try OpenMeteoDecoding.decodeHistoricalUV(uvBody(time: "[]", uv: "[]")) }
        #expect(throws: WeatherError.decoding) { try OpenMeteoDecoding.decodeHistoricalUV(uvBody(tz: "\"Mars/Olympus\"")) }
        #expect(throws: WeatherError.decoding) { try OpenMeteoDecoding.decodeHistoricalUV(Data("not json".utf8)) }
        #expect(throws: WeatherError.decoding) { try OpenMeteoDecoding.decodeForecast(forecastBody(is_day: "[2,0]", daily: dailyOK)) }
        #expect(throws: WeatherError.decoding) { try OpenMeteoDecoding.decodeForecast(forecastBody()) }
    }

    @Test func syntheticDaily() throws {
        let valid = try OpenMeteoDecoding.decodeForecast(forecastBody(daily: dailyOK))
        #expect(valid.days.count == 1)
        #expect(valid.isDay == [true, false])
        let emptyDaily = """
            {"time":[],"weather_code":[],"sunrise":[],"sunset":[],"temperature_2m_max":[],"temperature_2m_min":[]}
            """
        #expect(try OpenMeteoDecoding.decodeForecast(forecastBody(daily: emptyDaily)).days.isEmpty)

        var columns = Metric.allCases.map { "\"\($0.apiName)\":[1,2]" }
        columns.append(contentsOf: ["\"weather_code\":[1,2]", "\"is_day\":[1,0]"])
        let noOffset = Data("""
            {"timezone":"UTC","hourly":{"time":[0,3600],\(columns.joined(separator: ","))},"daily":\(dailyOK)}
            """.utf8)
        #expect(throws: WeatherError.decoding) { try OpenMeteoDecoding.decodeForecast(noOffset) }
    }

    @Test func hourlyGrid() throws {
        let start = Date(timeIntervalSince1970: 0)
        let first = try HourlyGrid(start: start, count: 2, values: [.temperature: [.nan, 1]])
        let second = try HourlyGrid(start: start, count: 2, values: [.temperature: [.nan, 1]])
        #expect(first == second)
        #expect(first.value(.temperature, at: 0) == nil)
        #expect(first.value(.temperature, at: 2) == nil)
        #expect(first.value(.temperature, at: -1) == nil)
        #expect(first.value(.pressure, at: 1) == nil)
        #expect(throws: WeatherError.decoding) { try HourlyGrid(start: start, count: 3, values: [.temperature: [1]]) }
    }
}
