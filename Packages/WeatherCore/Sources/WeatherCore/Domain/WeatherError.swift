public enum WeatherError: Error, Sendable, Equatable {
    /// Transport failed, or HTTP 5xx.
    case network
    /// HTTP 429.
    case rateLimited
    /// Other HTTP 4xx: the API refused our request.
    case rejected(statusCode: Int)
    /// Body does not decode or breaks the contract.
    case decoding
    /// Empty hourly grid (`hourly.time = []`).
    case noData
}
