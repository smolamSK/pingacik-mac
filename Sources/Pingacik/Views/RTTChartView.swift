import SwiftUI
import Charts
import PingacikCore

/// RTT line over the downsampled buckets, with loss shaded in the critical
/// color proportional to how many pings in each bucket were lost, and dashed
/// rules at the warning/critical latency thresholds.
struct RTTChartView: View {
    let buckets: [RTTBucket]
    @ObservedObject var config: Config

    var body: some View {
        Chart {
            ForEach(Array(buckets.enumerated()), id: \.offset) { _, bucket in
                if bucket.lossCount > 0 {
                    RectangleMark(
                        x: .value("Time", bucket.t),
                        yStart: .value("Bottom", 0),
                        yEnd: .value("Top", chartMax)
                    )
                    .foregroundStyle(config.color(for: .critical).opacity(lossOpacity(bucket)))
                }
                if bucket.avg >= 0 {
                    AreaMark(
                        x: .value("Time", bucket.t),
                        yStart: .value("Min", bucket.min),
                        yEnd: .value("Max", bucket.max)
                    )
                    .foregroundStyle(config.color(for: .ok).opacity(0.15))

                    LineMark(
                        x: .value("Time", bucket.t),
                        y: .value("RTT", bucket.avg)
                    )
                    .foregroundStyle(config.color(for: .ok))
                    .interpolationMethod(.monotone)
                }
            }

            RuleMark(y: .value("Warning threshold", Double(config.yellowMs)))
                .foregroundStyle(config.color(for: .warning).opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            RuleMark(y: .value("Critical threshold", Double(config.redMs)))
                .foregroundStyle(config.color(for: .critical).opacity(0.6))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .chartYScale(domain: 0...chartMax)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
    }

    private var chartMax: Double {
        let peak = buckets.map(\.max).filter { $0 >= 0 }.max() ?? 0
        return max(peak * 1.2, Double(config.redMs) * 1.2, 10)
    }

    private func lossOpacity(_ bucket: RTTBucket) -> Double {
        guard bucket.total > 0 else { return 0 }
        let fraction = Double(bucket.lossCount) / Double(bucket.total)
        return 0.15 + 0.5 * fraction
    }
}
