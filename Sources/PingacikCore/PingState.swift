import Foundation

// Pure data logic for Pingacik: classification, the hysteresis state machine,
// scheduling, buffering and downsampling. Deliberately free of AppKit/SwiftUI
// so it can be exercised standalone in unit tests.

public enum ConnectionStatus: Int, Comparable, Sendable {
    case ok = 0
    case warning = 1
    case critical = 2

    public static func < (lhs: ConnectionStatus, rhs: ConnectionStatus) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum Verdict {
    case good
    case slowWarning
    case slowCritical
    case lost
}

/// Latency/loss thresholds driving both classification and the state machine.
public struct Thresholds: Sendable {
    public var yellowAfter: Int
    public var redAfter: Int
    public var recoverAfter: Int
    public var yellowMs: Double
    public var redMs: Double

    public init(yellowAfter: Int, redAfter: Int, recoverAfter: Int, yellowMs: Double, redMs: Double) {
        self.yellowAfter = yellowAfter
        self.redAfter = redAfter
        self.recoverAfter = recoverAfter
        self.yellowMs = yellowMs
        self.redMs = redMs
    }
}

/// Classify a single sample against the latency thresholds.
func classify(_ sample: PingSample, _ cfg: Thresholds) -> Verdict {
    guard sample.ok else { return .lost }
    if sample.rtt > cfg.redMs { return .slowCritical }
    if sample.rtt > cfg.yellowMs { return .slowWarning }
    return .good
}

public func sampleStatus(_ sample: PingSample, thresholds: Thresholds) -> ConnectionStatus {
    switch classify(sample, thresholds) {
    case .good: return .ok
    case .slowWarning: return .warning
    case .slowCritical, .lost: return .critical
    }
}

/// Hysteresis state machine: degrades immediately, recovers slowly.
///
/// A worse verdict applies at once, but returning to OK requires
/// `recoverAfter` consecutive fully-good samples.
public struct PingStateMachine: Sendable {
    public private(set) var status: ConnectionStatus = .ok
    public private(set) var consecutiveLoss = 0
    public private(set) var consecutiveSlowWarning = 0
    public private(set) var consecutiveSlowCritical = 0
    public private(set) var consecutiveGood = 0

    public init() {}

    /// Advance the machine by one sample. Mutates and returns `status`.
    @discardableResult
    public mutating func advance(with sample: PingSample, thresholds cfg: Thresholds) -> ConnectionStatus {
        let verdict = classify(sample, cfg)

        // Counters. Each is reset by any sample that does not extend its run.
        consecutiveLoss = verdict == .lost ? consecutiveLoss + 1 : 0

        // A critical-level sample also extends the warning-level run: it is
        // over both thresholds, so a slow link ramps OK -> Warning -> Critical
        // rather than flapping.
        switch verdict {
        case .slowCritical:
            consecutiveSlowCritical += 1
            consecutiveSlowWarning += 1
        case .slowWarning:
            consecutiveSlowCritical = 0
            consecutiveSlowWarning += 1
        case .good, .lost:
            consecutiveSlowCritical = 0
            consecutiveSlowWarning = 0
        }

        consecutiveGood = verdict == .good ? consecutiveGood + 1 : 0

        let lossState: ConnectionStatus =
            consecutiveLoss >= cfg.redAfter ? .critical
            : consecutiveLoss >= cfg.yellowAfter ? .warning
            : .ok

        let latencyState: ConnectionStatus =
            consecutiveSlowCritical >= cfg.redAfter ? .critical
            : consecutiveSlowWarning >= cfg.yellowAfter ? .warning
            : .ok

        let target = max(lossState, latencyState)

        if target > status {
            // Worse than now: apply immediately.
            status = target
        } else if status != .ok && consecutiveGood >= cfg.recoverAfter {
            // Better than now, and the link has proven itself: go straight to OK.
            status = .ok
        }
        // Otherwise hold the current (degraded) status.

        return status
    }
}

/// How long to wait before starting the next ping, measured from when the
/// previous one *started* rather than when it finished.
///
/// This keeps the cadence at `intervalMs` regardless of how long a reply
/// took, instead of drifting by the round-trip time on every sample. When a
/// ping overruns the interval, the next one follows after `minGapMs`, so the
/// sample rate degrades to the timeout rather than collapsing to a multiple
/// of the interval.
public func nextDelay(intervalMs: Double, elapsedMs: Double, minGapMs: Double) -> Double {
    max(minGapMs, intervalMs - elapsedMs)
}

/// Append to a ring buffer capped at `cap` entries.
public func pushSample(_ buffer: inout [PingSample], _ sample: PingSample, cap: Int) {
    buffer.append(sample)
    while buffer.count > cap {
        buffer.removeFirst()
    }
}

/// The tail of `buffer` covering the last `seconds`, relative to `now`.
public func windowSlice(_ buffer: [PingSample], seconds: Double, now: Date) -> ArraySlice<PingSample> {
    let cutoff = now.addingTimeInterval(-seconds)
    var i = buffer.count
    while i > 0 && buffer[i - 1].t >= cutoff {
        i -= 1
    }
    return buffer[i...]
}

/// One bucket of downsampled chart data.
public struct RTTBucket: Sendable, Equatable {
    public var t: Date
    public var avg: Double
    public var min: Double
    public var max: Double
    public var lossCount: Int
    public var total: Int
}

/// Bucket `slice` down to at most `targetPoints` points so the chart stays
/// readable and cheap on long timescales.
public func downsample(_ slice: some Collection<PingSample>, targetPoints: Int) -> [RTTBucket] {
    let slice = Array(slice)
    guard !slice.isEmpty else { return [] }

    if slice.count <= targetPoints {
        return slice.map { s in
            RTTBucket(
                t: s.t,
                avg: s.ok ? s.rtt : -1,
                min: s.ok ? s.rtt : -1,
                max: s.ok ? s.rtt : -1,
                lossCount: s.ok ? 0 : 1,
                total: 1
            )
        }
    }

    let bucketSize = Double(slice.count) / Double(targetPoints)
    var out: [RTTBucket] = []
    out.reserveCapacity(targetPoints)

    for b in 0..<targetPoints {
        let start = Int(Double(b) * bucketSize)
        var end = Int(Double(b + 1) * bucketSize)
        if end <= start { end = start + 1 }

        var sum = 0.0
        var n = 0
        var lost = 0
        var mn = Double.infinity
        var mx = -Double.infinity

        var i = start
        while i < end && i < slice.count {
            let s = slice[i]
            if s.ok {
                sum += s.rtt
                n += 1
                if s.rtt < mn { mn = s.rtt }
                if s.rtt > mx { mx = s.rtt }
            } else {
                lost += 1
            }
            i += 1
        }

        out.append(RTTBucket(
            t: slice[start].t,
            avg: n > 0 ? sum / Double(n) : -1,
            min: n > 0 ? mn : -1,
            max: n > 0 ? mx : -1,
            lossCount: lost,
            total: min(end, slice.count) - start
        ))
    }
    return out
}

/// Aggregate stats over a slice, for the popup header.
public struct PingStats: Sendable, Equatable {
    public var count: Int
    public var received: Int
    public var lost: Int
    public var lossPercent: Double
    public var avg: Double
    public var min: Double
    public var max: Double
}

public func stats(_ slice: some Collection<PingSample>) -> PingStats {
    var sum = 0.0
    var n = 0
    var lost = 0
    var mn = Double.infinity
    var mx = -Double.infinity

    for s in slice {
        if s.ok {
            sum += s.rtt
            n += 1
            if s.rtt < mn { mn = s.rtt }
            if s.rtt > mx { mx = s.rtt }
        } else {
            lost += 1
        }
    }

    let count = slice.count
    return PingStats(
        count: count,
        received: n,
        lost: lost,
        lossPercent: count > 0 ? Double(lost) * 100 / Double(count) : 0,
        avg: n > 0 ? sum / Double(n) : -1,
        min: n > 0 ? mn : -1,
        max: n > 0 ? mx : -1
    )
}
