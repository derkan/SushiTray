import Foundation

struct RollingMetric {
    private(set) var samples: [(at: Date, value: Double)] = []
    var window: TimeInterval
    private(set) var lastValue: Double?

    init(window: TimeInterval = 3) {
        self.window = window
    }

    mutating func latest(now: Date = Date()) -> Double? {
        prune(now: now)
        return samples.last?.value
    }

    mutating func record(_ value: Double, at date: Date = Date()) {
        lastValue = value
        samples.append((at: date, value: value))
        prune(now: date)
    }

    mutating func prune(now: Date = Date()) {
        samples.removeAll { now.timeIntervalSince($0.at) > window }
    }

    mutating func reset() {
        samples.removeAll()
        lastValue = nil
    }

    mutating func stickyLatest(now: Date = Date()) -> Double? {
        if let live = latest(now: now) { return live }
        return lastValue
    }
}
