import Foundation

struct ChartPoint: Identifiable, Hashable {
    let id: Int
    let value: Double
}

/// Fixed-length history; ids keep increasing so charts slide instead of redrawing from zero.
struct Series {
    let capacity: Int
    private(set) var points: [ChartPoint] = []
    private var next = 0

    init(capacity: Int = 90) { self.capacity = capacity }

    mutating func append(_ value: Double) {
        points.append(ChartPoint(id: next, value: value.isFinite ? value : 0))
        next += 1
        if points.count > capacity { points.removeFirst(points.count - capacity) }
    }

    var last: Double { points.last?.value ?? 0 }
    var maxValue: Double { points.map(\.value).max() ?? 0 }

    func average(last n: Int) -> Double {
        let slice = points.suffix(n)
        return slice.isEmpty ? 0 : slice.map(\.value).reduce(0, +) / Double(slice.count)
    }

    var xDomain: ClosedRange<Int> {
        let hi = next - 1
        return (hi - capacity + 1)...hi
    }
}

/// One metric at three resolutions: every sample for the last few minutes, 20-second averages for an
/// hour, and 5-minute averages for a day. Memory stays constant however long the app runs.
struct History {
    private(set) var live = Series(capacity: 90)
    private(set) var hour = Series(capacity: 180)
    private(set) var day = Series(capacity: 288)
    private var hourBucket = Bucket(interval: 20)
    private var dayBucket = Bucket(interval: 300)

    private struct Bucket {
        let interval: TimeInterval
        var sum = 0.0
        var count = 0
        var started: Date?

        mutating func add(_ value: Double, at time: Date) -> Double? {
            if started == nil { started = time }
            sum += value
            count += 1
            guard let started, time.timeIntervalSince(started) >= interval else { return nil }
            let average = sum / Double(count)
            sum = 0
            count = 0
            self.started = time
            return average
        }
    }

    mutating func append(_ value: Double, at time: Date = Date()) {
        live.append(value)
        if let avg = hourBucket.add(value, at: time) { hour.append(avg) }
        if let avg = dayBucket.add(value, at: time) { day.append(avg) }
    }

    subscript(range: ChartRange) -> Series {
        switch range {
        case .live: live
        case .hour: hour
        case .day: day
        }
    }

    var last: Double { live.last }
    var maxValue: Double { live.maxValue }
    func average(last n: Int) -> Double { live.average(last: n) }
}
