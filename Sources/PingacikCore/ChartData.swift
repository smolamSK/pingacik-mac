import Foundation

public struct ChartPoint: Identifiable {
    public let id: Int
    public let segment: Int
    public let bucket: RTTBucket
}

public struct LossBand: Identifiable {
    public let id: UUID
    public let start: Date
    public let end: Date
}

/// Each uninterrupted run is bucketed separately, so aggregation cannot hide an outage.
public struct ChartData {
    public let points: [ChartPoint]
    public let losses: [LossBand]

    public init(samples: [PingSample], interval: Double, timeout: Double, targetPoints: Int = 300) {
        var runs: [[PingSample]] = []
        var run: [PingSample] = []
        var previous: PingSample?
        var bands: [LossBand] = []
        let maxGap = max(interval * 2, interval + timeout + 1)
        for sample in samples {
            if !sample.ok || previous.map({ sample.sessionID != $0.sessionID || sample.startedAt.timeIntervalSince($0.t) > maxGap }) == true {
                if !run.isEmpty { runs.append(run); run = [] }
            }
            if sample.ok {
                run.append(sample)
            } else {
                bands.append(LossBand(id: sample.id, start: sample.startedAt,
                                      end: max(sample.t, sample.startedAt.addingTimeInterval(0.05))))
            }
            previous = sample
        }
        if !run.isEmpty { runs.append(run) }
        var points: [ChartPoint] = []
        for (segment, samplesInRun) in runs.enumerated() {
            let budget = max(2, Int(ceil(Double(max(1, targetPoints) * samplesInRun.count) / Double(max(1, samples.count)))))
            for bucket in downsample(samplesInRun, targetPoints: budget) {
                points.append(ChartPoint(id: points.count, segment: segment, bucket: bucket))
            }
        }
        self.points = points
        self.losses = bands
    }

    public func upperBound(criticalThreshold: Double, includeThresholds: Bool) -> Double {
        let peak = points.map(\.bucket.max).max() ?? 0
        return max(10, peak * 1.2, includeThresholds ? criticalThreshold * 1.2 : 0)
    }
}
