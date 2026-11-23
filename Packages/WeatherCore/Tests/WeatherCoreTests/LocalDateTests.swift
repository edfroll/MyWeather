import Foundation
import Testing
import WeatherCore

struct LocalDateTests {
    @Test func iso8601IsZeroPadded() {
        #expect(LocalDate(year: 2026, month: 1, day: 5).iso8601 == "2026-01-05")
    }

    @Test(arguments: [("Pacific/Auckland", 13), ("UTC", 12), ("America/New_York", 12)])
    func dayInZone(zone: String, day: Int) throws {
        let now = Date(timeIntervalSince1970: 1_794_504_285) // 2026-11-12T17:24:45Z
        let timeZone = try #require(TimeZone(identifier: zone))
        #expect(LocalDate(now, in: timeZone) == LocalDate(year: 2026, month: 11, day: day))
    }

    @Test func comparison() {
        #expect(LocalDate(year: 2025, month: 12, day: 31) < LocalDate(year: 2026, month: 1, day: 1))
        #expect(LocalDate(year: 2026, month: 1, day: 9) < LocalDate(year: 2026, month: 2, day: 1))
        #expect(LocalDate(year: 2026, month: 2, day: 1) < LocalDate(year: 2026, month: 2, day: 2))
    }
}
