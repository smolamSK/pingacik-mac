import SwiftUI
import PingacikCore

private let timescales: [(label: String, seconds: Double)] = [
    ("30s", 30), ("1m", 60), ("5m", 300), ("15m", 900), ("1h", 3600)
]

private let logTimeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    return f
}()

/// Full representation: header stats, a timescale picker, the RTT chart and
/// a live log of recent samples.
struct PopoverView: View {
    @ObservedObject var monitor: PingMonitor
    @ObservedObject var config: Config
    var openSettings: () -> Void
    @State private var selectedSeconds: Double

    init(monitor: PingMonitor, config: Config, openSettings: @escaping () -> Void) {
        self.monitor = monitor
        self.config = config
        self.openSettings = openSettings
        _selectedSeconds = State(initialValue: Double(config.defaultTimescale))
    }

    private var windowStats: PingStats { monitor.stats(overLast: selectedSeconds) }
    private var buckets: [RTTBucket] { monitor.buckets(overLast: selectedSeconds) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Picker("Timescale", selection: $selectedSeconds) {
                ForEach(timescales, id: \.seconds) { ts in
                    Text(ts.label).tag(ts.seconds)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            RTTChartView(buckets: buckets, config: config)
                .frame(height: 160)

            Divider()

            logList

            Divider()

            HStack {
                Button("Settings…", action: openSettings)
                Spacer()
                Button("Quit Pingacik") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                StatusDot(status: monitor.connectionStatus, config: config, diameter: 10)
                Text(monitor.host).font(.headline)
                Spacer()
                Text(statusText)
                    .foregroundStyle(config.color(for: monitor.connectionStatus))
            }

            if monitor.sampleCount == 0 {
                Text("Waiting for first reply…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Latest: \(latestText) · Avg: \(fmt(windowStats.avg)) ms · Loss: \(String(format: "%.1f", windowStats.lossPercent))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Min: \(fmt(windowStats.min)) ms · Max: \(fmt(windowStats.max)) ms")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        switch monitor.connectionStatus {
        case .ok: return "OK"
        case .warning: return "Warning"
        case .critical: return "Critical"
        }
    }

    private var latestText: String {
        monitor.lastOk ? "\(fmt(monitor.lastRtt)) ms" : "timed out"
    }

    private func fmt(_ v: Double) -> String {
        v >= 0 ? String(format: "%.1f", v) : "—"
    }

    private var logList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(monitor.recentLog.prefix(50).enumerated()), id: \.offset) { _, sample in
                    HStack {
                        Circle()
                            .fill(sample.ok ? config.color(for: .ok) : config.color(for: .critical))
                            .frame(width: 6, height: 6)
                        Text(logTimeFormatter.string(from: sample.t))
                            .font(.system(.caption, design: .monospaced))
                        Spacer()
                        Text(sample.ok ? "\(fmt(sample.rtt)) ms" : "timed out")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(height: 120)
    }
}
