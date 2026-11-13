import Foundation

public struct HourlyGrid: Sendable, Equatable {
    public static let step: TimeInterval = 3600
    /// Absolute instant of index 0; not necessarily a whole UTC hour (+05:30).
    public let start: Date
    public let count: Int
    /// NaN = no value (D-3); every array has `count` elements.
    package let values: [Metric: [Float]]

    /// Throws `.decoding` if any array's length differs from `count`, or `count < 0`.
    package init(start: Date, count: Int, values: [Metric: [Float]]) throws(WeatherError) {
        guard count >= 0, values.values.allSatisfy({ $0.count == count }) else { throw .decoding }
        self.start = start
        self.count = count
        self.values = values
    }

    public var metrics: Set<Metric> { Set(values.keys) }

    public func date(at index: Int) -> Date {
        start.addingTimeInterval(Double(index) * Self.step)
    }

    /// nil: metric not in this grid, index out of 0..<count, or the stored value is NaN (null in the response).
    public func value(_ metric: Metric, at index: Int) -> Float? {
        guard index >= 0, index < count, let column = values[metric] else { return nil }
        let value = column[index]
        return value.isNaN ? nil : value
    }

    public static func == (lhs: HourlyGrid, rhs: HourlyGrid) -> Bool {
        guard lhs.start == rhs.start, lhs.count == rhs.count,
              Set(lhs.values.keys) == Set(rhs.values.keys) else { return false }
        for (metric, left) in lhs.values {
            guard let right = rhs.values[metric] else { return false }
            for (a, b) in zip(left, right) where !(a == b || (a.isNaN && b.isNaN)) { return false }
        }
        return true
    }
}
