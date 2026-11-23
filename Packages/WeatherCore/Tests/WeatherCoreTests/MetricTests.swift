import Testing
import WeatherCore

struct MetricTests {
    @Test func elevenCasesInProductOrder() {
        #expect(Metric.allCases.count == 11)
        #expect(Metric.allCases.map(\.apiName) == [
            "temperature_2m", "apparent_temperature", "relative_humidity_2m", "precipitation",
            "precipitation_probability", "wind_speed_10m", "wind_gusts_10m", "wind_direction_10m",
            "pressure_msl", "cloud_cover", "uv_index",
        ])
    }

    @Test func chips() {
        #expect(Metric.forecastChips.count == 9)
        #expect(Metric.forecastChips == Metric.chipOrder)
        #expect(Metric.historyChips.count == 8)
        #expect(!Metric.historyChips.contains(.precipitationProbability))
        #expect(Metric.historyChips == Metric.chipOrder.filter { $0 != .precipitationProbability })
        #expect(Set(Metric.chipOrder) == Set(Metric.allCases.filter(\.isChipSelectable)))
    }

    @Test func windStoredInMetersPerSecond() {
        #expect(Metric.windSpeed.siUnit == .metersPerSecond)
        #expect(Metric.windGusts.siUnit == .metersPerSecond)
    }
}
