import Foundation

public struct OpenMeteoClient: Sendable {
    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    // Throw WeatherError or CancellationError (D-6).
    package func forecast(at coordinate: Coordinate) async throws -> Forecast {
        let data = try await send(.forecast(at: coordinate))
        return try await OpenMeteoDecoding.forecast(from: data)
    }

    package func archive(at coordinate: Coordinate, dates: ClosedRange<LocalDate>) async throws -> ArchiveData {
        let data = try await send(.history(.archive, at: coordinate, dates: dates))
        return try await OpenMeteoDecoding.archive(from: data)
    }

    package func historicalUV(at coordinate: Coordinate, dates: ClosedRange<LocalDate>) async throws -> HourlyGrid {
        let data = try await send(.history(.historicalUV, at: coordinate, dates: dates))
        return try await OpenMeteoDecoding.historicalUV(from: data)
    }

    private func send(_ request: OpenMeteoRequest) async throws -> Data {
        let result: (Data, HTTPURLResponse)
        do {
            result = try await transport.data(for: URLRequest(url: request.url))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw WeatherError.network
        }
        switch result.1.statusCode {
        case 200...299: return result.0
        case 429: throw WeatherError.rateLimited
        case 400...499: throw WeatherError.rejected(statusCode: result.1.statusCode)
        default: throw WeatherError.network
        }
    }
}
