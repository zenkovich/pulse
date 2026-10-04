import Foundation

/// Time-ordered snapshots for the last `window` seconds.
public struct History {
    public private(set) var samples: [Snapshot] = []
    public let window: TimeInterval

    public init(window: TimeInterval = 3600) {
        self.window = window
    }

    public var last: Snapshot? { samples.last }

    public mutating func append(_ snapshot: Snapshot) {
        if let last = samples.last, snapshot.time < last.time {
            // The clock went back (manual change, NTP jump): old points would draw in the future.
            samples.removeAll()
        }
        samples.append(snapshot)
        // Prune in batches so appends stay O(1) amortised.
        if let first = samples.first, first.time < snapshot.time.addingTimeInterval(-window - 60) {
            samples.removeFirst(lowerBound(snapshot.time.addingTimeInterval(-window)))
        }
    }

    /// Index of the first sample at or after `time`.
    public func lowerBound(_ time: Date) -> Int {
        var low = 0, high = samples.count
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].time < time { low = mid + 1 } else { high = mid }
        }
        return low
    }

    public func recent(_ seconds: TimeInterval) -> ArraySlice<Snapshot> {
        guard let last = samples.last else { return [] }
        return samples[lowerBound(last.time.addingTimeInterval(-seconds))...]
    }

    public func suffix(_ count: Int) -> ArraySlice<Snapshot> {
        samples.suffix(count)
    }
}

/// One chart row: a time and one value per series.
public struct SeriesRow: Identifiable, Sendable {
    public let id: Int
    public let time: Date
    public let values: [Double]

    public init(id: Int, time: Date, values: [Double]) {
        self.id = id
        self.time = time
        self.values = values
    }
}

public enum Downsample {
    /// Averages samples into buckets aligned to absolute time, so buckets don't shift (and shimmer)
    /// as new samples arrive. Short ranges pass through one row per sample.
    public static func rows(_ slice: ArraySlice<Snapshot>, range: TimeInterval, maxPoints: Int,
                            _ extract: (Snapshot) -> [Double]) -> [SeriesRow] {
        guard !slice.isEmpty, maxPoints > 0 else { return [] }
        if slice.count <= maxPoints {
            return slice.enumerated().map { SeriesRow(id: $0.offset, time: $0.element.time, values: extract($0.element)) }
        }
        let bucket = range / Double(maxPoints)
        var rows: [SeriesRow] = []
        rows.reserveCapacity(maxPoints + 1)
        var currentKey: Int?
        var sums: [Double] = []
        var count = 0
        var times = 0.0

        func flush() {
            guard let key = currentKey, count > 0 else { return }
            rows.append(SeriesRow(id: key, time: Date(timeIntervalSinceReferenceDate: times / Double(count)),
                                  values: sums.map { $0 / Double(count) }))
        }

        for snapshot in slice {
            let t = snapshot.time.timeIntervalSinceReferenceDate
            let key = Int((t / bucket).rounded(.down))
            let values = extract(snapshot)
            if key != currentKey {
                flush()
                currentKey = key
                sums = values
                count = 1
                times = t
            } else {
                for i in 0..<min(sums.count, values.count) { sums[i] += values[i] }
                count += 1
                times += t
            }
        }
        flush()
        return rows
    }
}
