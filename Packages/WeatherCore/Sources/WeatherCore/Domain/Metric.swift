public enum Metric: String, CaseIterable, Sendable {
    // Order of product §2.2 = order of variables in requests (D-1). Not the chip order.
    case temperature, apparentTemperature, relativeHumidity, precipitation, precipitationProbability,
         windSpeed, windGusts, windDirection, pressure, cloudCover, uvIndex

    public var apiName: String {
        switch self {
        case .temperature: "temperature_2m"
        case .apparentTemperature: "apparent_temperature"
        case .relativeHumidity: "relative_humidity_2m"
        case .precipitation: "precipitation"
        case .precipitationProbability: "precipitation_probability"
        case .windSpeed: "wind_speed_10m"
        case .windGusts: "wind_gusts_10m"
        case .windDirection: "wind_direction_10m"
        case .pressure: "pressure_msl"
        case .cloudCover: "cloud_cover"
        case .uvIndex: "uv_index"
        }
    }

    public var siUnit: MetricUnit {
        switch self {
        case .temperature, .apparentTemperature: .celsius
        case .relativeHumidity, .precipitationProbability, .cloudCover: .percent
        case .precipitation: .millimeters
        case .windSpeed, .windGusts: .metersPerSecond
        case .windDirection: .degrees
        case .pressure: .hectopascals
        case .uvIndex: .dimensionless
        }
    }

    public var isChipSelectable: Bool {
        switch self {
        case .precipitation, .windDirection: false
        case .temperature, .apparentTemperature, .relativeHumidity, .precipitationProbability,
             .windSpeed, .windGusts, .pressure, .cloudCover, .uvIndex: true
        }
    }

    public var hasHistory: Bool {
        switch self {
        case .precipitationProbability: false
        case .temperature, .apparentTemperature, .relativeHumidity, .precipitation,
             .windSpeed, .windGusts, .windDirection, .pressure, .cloudCover, .uvIndex: true
        }
    }

    /// Chip order, UX §5.1.
    public static let chipOrder: [Metric] = [
        .temperature, .apparentTemperature, .precipitationProbability, .relativeHumidity,
        .windSpeed, .windGusts, .cloudCover, .pressure, .uvIndex,
    ]
    public static var forecastChips: [Metric] { chipOrder }
    public static var historyChips: [Metric] { chipOrder.filter(\.hasHistory) }
}

public enum MetricUnit: Sendable, Equatable {
    case celsius, percent, millimeters, metersPerSecond, degrees, hectopascals, dimensionless
}
