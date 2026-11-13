import Foundation
import Testing
import WeatherCore

struct OpenMeteoClientTests {
    private let tokyo = Coordinate(latitude: 35.6895, longitude: 139.6917)
    private let dates = LocalDate(year: 2026, month: 11, day: 5)...LocalDate(year: 2026, month: 11, day: 13)

    private func client(status: Int, fixture: String?) -> OpenMeteoClient {
        OpenMeteoClient(transport: StubTransport { request in
            let body = try fixture.map { try Fixture.data($0) } ?? Data()
            return (body, try httpResponse(status, url: request.url ?? URL(fileURLWithPath: "/")))
        })
    }

    private func client(throwing error: any Error) -> OpenMeteoClient {
        OpenMeteoClient(transport: StubTransport { _ in throw error })
    }

    @Test func forecastSuccess() async throws {
        let log = CallLog()
        let client = OpenMeteoClient(transport: StubTransport { request in
            await log.record(request)
            return (try Fixture.data("forecast-tokyo"), try httpResponse(200))
        })
        let forecast = try await client.forecast(at: tokyo)
        #expect(forecast.timeZone.identifier == "Asia/Tokyo")
        let requests = await log.requests
        #expect(requests.count == 1)
        #expect(requests.first?.url == OpenMeteoRequest.forecast(at: tokyo).url)
    }

    @Test func rateLimited() async {
        await #expect(throws: WeatherError.rateLimited) {
            try await client(status: 429, fixture: "error-429").forecast(at: tokyo)
        }
    }

    @Test func rejected() async {
        await #expect(throws: WeatherError.rejected(statusCode: 400)) {
            try await client(status: 400, fixture: "archive-auckland-end-today").archive(at: tokyo, dates: dates)
        }
    }

    @Test func networkFailures() async {
        await #expect(throws: WeatherError.network) {
            try await client(status: 503, fixture: nil).forecast(at: tokyo)
        }
        await #expect(throws: WeatherError.network) {
            try await client(throwing: URLError(.notConnectedToInternet)).forecast(at: tokyo)
        }
    }

    @Test func cancellation() async {
        await #expect(throws: CancellationError.self) {
            try await client(throwing: URLError(.cancelled)).forecast(at: tokyo)
        }
        await #expect(throws: CancellationError.self) {
            try await client(throwing: CancellationError()).forecast(at: tokyo)
        }
    }

    @Test func historicalUV() async throws {
        let grid = try await client(status: 200, fixture: "historical-forecast-auckland-end-today")
            .historicalUV(at: tokyo, dates: dates)
        #expect(grid.metrics == [.uvIndex])
    }
}
