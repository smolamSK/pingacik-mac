import SwiftUI
import Charts
import PingacikCore

struct RTTChartView: View {
    let data: ChartData
    let domain: ClosedRange<Date>
    let includeThresholds: Bool
    @ObservedObject var config: Config

    private var chartMax: Double {
        data.upperBound(criticalThreshold: Double(config.redMs), includeThresholds: includeThresholds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(data.losses) { loss in
                    RectangleMark(
                        xStart: .value("Start", max(domain.lowerBound, loss.start)),
                        xEnd: .value("End", min(domain.upperBound, loss.end)),
                        yStart: .value("Bottom", 0), yEnd: .value("Top", chartMax)
                    )
                    .foregroundStyle(config.color(for: .critical).opacity(0.18))
                    .accessibilityLabel("Failed probe")
                }
                ForEach(data.points) { point in
                    let bucket = point.bucket
                    RuleMark(x: .value("Time", bucket.t), yStart: .value("Minimum", bucket.min), yEnd: .value("Maximum", bucket.max))
                        .foregroundStyle(Color.accentColor.opacity(0.25))
                    LineMark(x: .value("Time", bucket.t), y: .value("RTT", bucket.avg), series: .value("Run", point.segment))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                        .interpolationMethod(.linear)
                    PointMark(x: .value("Time", bucket.t), y: .value("RTT", bucket.avg))
                        .symbolSize(8)
                        .foregroundStyle(pointColor(bucket.avg))
                }
                if Double(config.yellowMs) <= chartMax {
                    RuleMark(y: .value("Warning", Double(config.yellowMs)))
                        .foregroundStyle(config.color(for: .warning).opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                if Double(config.redMs) <= chartMax {
                    RuleMark(y: .value("Critical", Double(config.redMs)))
                        .foregroundStyle(config.color(for: .critical).opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: 0...chartMax)
            .chartYAxisLabel("ms")
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: domain.upperBound.timeIntervalSince(domain.lowerBound) > 300
                                   ? .dateTime.hour().minute() : .dateTime.minute().second())
                }
            }
            .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
            .chartLegend(.hidden)
            .overlay {
                if data.points.isEmpty && data.losses.isEmpty {
                    Text("Waiting for measurements")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            HStack(spacing: 12) {
                thresholdLabel("Warning", value: config.yellowMs, status: .warning)
                thresholdLabel("Critical", value: config.redMs, status: .critical)
                Spacer(minLength: 0)
                Label("Failed probe", systemImage: "rectangle.fill")
                    .foregroundStyle(config.color(for: .critical))
            }
            .font(.system(size: 10))
        }
    }

    private func thresholdLabel(_ name: String, value: Int, status: ConnectionStatus) -> some View {
        Text("\(name) \(value)\(Double(value) > chartMax ? " ↑" : "")")
            .foregroundStyle(config.color(for: status))
            .help("\(name) threshold: \(value) ms\(Double(value) > chartMax ? " (above the visible scale)" : "")")
            .accessibilityLabel("\(name) threshold \(value) milliseconds\(Double(value) > chartMax ? ", above visible scale" : "")")
    }

    private func pointColor(_ rtt: Double) -> Color {
        config.color(for: rtt > Double(config.redMs) ? .critical : rtt > Double(config.yellowMs) ? .warning : .ok)
    }
}
