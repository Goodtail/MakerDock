import Foundation

/// One pending print per model. Requeue a model after completion to plan another copy.
public struct PrintQueueEntry: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public var addedAt: Date
    public var durationSeconds: Double?
    public init(id: String, addedAt: Date = Date(), durationSeconds: Double? = nil) {
        self.id = id; self.addedAt = addedAt; self.durationSeconds = durationSeconds
    }
}

public struct PrintQueueJob: Sendable {
    public let id: String
    public let seconds: Double?
    public init(id: String, seconds: Double?) { self.id = id; self.seconds = seconds }
}

/// Sequential, manually planned printing. Unknown durations never count as zero.
public struct PrintQueuePlan: Sendable {
    public struct Row: Sendable, Identifiable {
        public let id: String
        public let seconds: Double?
        public let startOffset: Double?
        public let endOffset: Double?
        public let fits: Bool
    }
    public let rows: [Row]
    public let knownSeconds: Double
    public let unknownCount: Int
    public let totalSeconds: Double?
    public let fitsCount: Int
    public let remainingSeconds: Double

    public static func duration(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0, value <= 31_536_000 else { return nil }
        return value
    }

    public init(jobs: [PrintQueueJob], availableSeconds: Double, changeoverSeconds: Double = 0) {
        let budget = availableSeconds.isFinite ? max(0, availableSeconds) : 0
        let gap = changeoverSeconds.isFinite ? max(0, changeoverSeconds) : 0
        var result: [Row] = [], cursor: Double? = 0, blocked = false, used = 0.0, fits = 0
        var known = 0.0, unknown = 0
        for (index, job) in jobs.enumerated() {
            let seconds = Self.duration(job.seconds)
            if let seconds { known += seconds } else { unknown += 1 }
            let start = cursor.map { $0 + (index == 0 ? 0 : gap) }
            let end: Double? = start.flatMap { start in seconds.map { start + $0 } }
            let fitsWindow = !blocked && end.map { $0 <= budget } == true
            if fitsWindow { fits += 1; used = end! } else { blocked = true }
            result.append(Row(id: job.id, seconds: seconds, startOffset: seconds == nil ? nil : start, endOffset: end, fits: fitsWindow))
            cursor = end
        }
        rows = result; knownSeconds = known; unknownCount = unknown
        totalSeconds = jobs.isEmpty ? 0 : cursor
        fitsCount = fits; remainingSeconds = max(0, budget - used)
    }

    /// Greedy selection in the user's priority order, followed by all deferred items.
    /// This is an explicit reorder operation, not a promise of optimal packing.
    public static func fittingOrder(jobs: [PrintQueueJob], availableSeconds: Double, changeoverSeconds: Double) -> [String] {
        var remaining = availableSeconds.isFinite ? max(0, availableSeconds) : 0
        let gap = changeoverSeconds.isFinite ? max(0, changeoverSeconds) : 0
        var chosen: [String] = [], deferred: [String] = []
        for job in jobs {
            guard let seconds = duration(job.seconds) else { deferred.append(job.id); continue }
            let cost = seconds + (chosen.isEmpty ? 0 : gap)
            if cost <= remaining { chosen.append(job.id); remaining -= cost }
            else { deferred.append(job.id) }
        }
        return chosen + deferred
    }
}
