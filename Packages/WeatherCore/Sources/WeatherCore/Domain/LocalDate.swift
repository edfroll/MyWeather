import Foundation

/// A calendar day in some time zone; used for `start_date` / `end_date` (A-22: dates are local days).
public struct LocalDate: Sendable, Hashable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day containing `instant` in `timeZone` (Gregorian calendar with that time zone, not Calendar.current — A-48).
    public init(_ instant: Date, in timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: instant)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// "yyyy-MM-dd", zero-padded. Built from the integers, no DateFormatter.
    public var iso8601: String {
        func pad(_ value: Int, _ width: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: max(0, width - text.count)) + text
        }
        return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))"
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}
