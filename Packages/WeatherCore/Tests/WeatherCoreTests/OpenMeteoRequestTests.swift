import Foundation
import Testing
import WeatherCore

struct OpenMeteoRequestTests {
    private struct Parts: Equatable {
        let host: String
        let path: String
        let items: [String: String]

        init(_ url: URL) throws {
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            host = components.host ?? ""
            path = components.path
            items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        }
    }

    private static let referenceNames: [String] = {
        let manifest = (try? Fixture.manifest()) ?? [:]
        return manifest.keys.filter { $0 != "error-429.json" }.sorted()
    }()

    @Test func referenceListIsNotEmpty() {
        #expect(Self.referenceNames.count > 30)
    }

    @Test(arguments: referenceNames)
    func matchesReference(name: String) throws {
        let entry = try #require(Fixture.manifest()[name])
        let reference = try Parts(try #require(URL(string: entry.url)))
        let items = reference.items
        let coordinate = Coordinate(latitude: Double(items["latitude"] ?? "") ?? 0,
                                    longitude: Double(items["longitude"] ?? "") ?? 0)
        let request: OpenMeteoRequest
        switch reference.host {
        case "api.open-meteo.com":
            request = .forecast(at: coordinate)
        case "archive-api.open-meteo.com", "historical-forecast-api.open-meteo.com":
            let start = try #require(LocalDate(iso: items["start_date"] ?? ""))
            let end = try #require(LocalDate(iso: items["end_date"] ?? ""))
            let source: HistorySource = reference.host.hasPrefix("archive") ? .archive : .historicalUV
            request = .history(source, at: coordinate, dates: start...end)
        case "geocoding-api.open-meteo.com":
            let language = try #require(SearchLanguage(rawValue: items["language"] ?? ""))
            request = .search(name: items["name"] ?? "", language: language)
        default:
            Issue.record("unknown host \(reference.host)")
            return
        }
        #expect(try Parts(request.url) == reference)
    }

    @Test func archiveEndDateAuckland() throws {
        let now = Date(timeIntervalSince1970: 1_794_504_285) // 2026-11-12T17:24:45Z
        let zone = try #require(TimeZone(identifier: "Pacific/Auckland"))
        #expect(HistorySource.archive.latestEndDate(now: now, timeZone: zone) == LocalDate(year: 2026, month: 11, day: 12))
        #expect(HistorySource.historicalUV.latestEndDate(now: now, timeZone: zone) == LocalDate(year: 2026, month: 11, day: 13))
    }

    @Test func endDateNewYorkEvening() throws {
        let now = Date(timeIntervalSince1970: 1_794_452_400) // 2026-11-12T03:00:00Z
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let expected = LocalDate(year: 2026, month: 11, day: 11)
        #expect(HistorySource.archive.latestEndDate(now: now, timeZone: zone) == expected)
        #expect(HistorySource.historicalUV.latestEndDate(now: now, timeZone: zone) == expected)
    }

    @Test func endDateMoscowDay() throws {
        let now = Date(timeIntervalSince1970: 1_794_484_800) // 2026-11-12T12:00:00Z
        let zone = try #require(TimeZone(identifier: "Europe/Moscow"))
        let expected = LocalDate(year: 2026, month: 11, day: 12)
        #expect(HistorySource.archive.latestEndDate(now: now, timeZone: zone) == expected)
        #expect(HistorySource.historicalUV.latestEndDate(now: now, timeZone: zone) == expected)
    }

    @Test func datesUsedAsGiven() throws {
        let request = OpenMeteoRequest.history(
            .archive, at: Coordinate(latitude: -36.8485, longitude: 174.7633),
            dates: LocalDate(year: 2026, month: 11, day: 5)...LocalDate(year: 2026, month: 11, day: 13))
        #expect(try Parts(request.url).items["end_date"] == "2026-11-13")
    }

    @Test func searchEncodesPlusAndAmpersand() throws {
        let plus = OpenMeteoRequest.search(name: "C++ Москва", language: .ru)
        let components = try #require(URLComponents(url: plus.url, resolvingAgainstBaseURL: false))
        #expect(try #require(components.percentEncodedQuery).contains("%2B%2B"))
        #expect(components.queryItems?.first { $0.name == "name" }?.value == "C++ Москва")

        let tricky = OpenMeteoRequest.search(name: "A&B=C", language: .en)
        let parsed = try #require(URLComponents(url: tricky.url, resolvingAgainstBaseURL: false))
        #expect(parsed.queryItems?.first { $0.name == "name" }?.value == "A&B=C")
        #expect(parsed.queryItems?.map(\.name) == ["name", "language", "count"])
    }
}
