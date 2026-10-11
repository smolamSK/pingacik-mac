import SwiftUI
import UniformTypeIdentifiers
import PingacikCore

private let timescales: [(label: String, seconds: Double)] = [
    ("30s", 30), ("1m", 60), ("5m", 300), ("15m", 900), ("1h", 3600)
]

struct PopoverView: View {
    @ObservedObject var monitor: PingMonitor
    @ObservedObject var config: Config
    var openSettings: () -> Void
    @State private var selectedSeconds: Double
    @State private var includeThresholds = false
    @State private var copied = false
    @State private var exportError: String?

    init(monitor: PingMonitor, config: Config, openSettings: @escaping () -> Void) {
        self.monitor = monitor
        self.config = config
        self.openSettings = openSettings
        _selectedSeconds = State(initialValue: Double(config.defaultTimescale))
    }

    private var statusColor: Color { monitor.isNeutral ? .secondary : config.color(for: monitor.displayStatus) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
        .padding(18)
        .frame(width: 440)
        .onAppear { selectedSeconds = Double(config.defaultTimescale) }
        .onChange(of: config.defaultTimescale) { _, value in selectedSeconds = Double(value) }
        .task(id: copied) {
            guard copied else { return }
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
        .alert("Could not export diagnostics", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private func content(now: Date) -> some View {
        let samples = monitor.samples(overLast: selectedSeconds, now: now)
        let summary = PingacikCore.stats(samples)
        let chart = ChartData(samples: samples, interval: Double(monitor.target.interval), timeout: Double(monitor.target.timeout))
        return VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(monitor.activity == .live && monitor.lastOk ? fmt(monitor.lastRtt) : "—")
                    .font(.system(size: 36, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("ms").font(.title3).foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("LATEST RTT").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    if let latest = monitor.latest {
                        Text(latest.t, style: .time).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(monitor.statusDetail).font(.caption).foregroundStyle(.secondary)
                if let diagnostic = monitor.latest?.diagnostic, monitor.activity == .live {
                    Text(diagnostic).font(.caption).foregroundStyle(.secondary).lineLimit(2).help(diagnostic)
                }
            }
            HStack(spacing: 0) {
                metric("Average", value: fmt(summary.avg), unit: "ms")
                Divider().frame(height: 30)
                metric("Loss", value: summary.count > 0 ? String(format: "%.1f", summary.lossPercent) : "—", unit: "%")
                    .help("Probes with no reply, including target and ping errors.")
                Divider().frame(height: 30)
                metric("Peak", value: fmt(summary.max), unit: "ms")
            }
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            Picker("Chart range", selection: $selectedSeconds) {
                ForEach(timescales, id: \.seconds) { Text($0.label).tag($0.seconds) }
            }
            .pickerStyle(.segmented).labelsHidden()
            HStack {
                Text("Latency").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Scale", selection: $includeThresholds) {
                    Text("Auto").tag(false)
                    Text("Thresholds").tag(true)
                }
                .labelsHidden().frame(width: 132).controlSize(.small)
                .help("Auto follows measured latency. Thresholds includes both warning and critical lines.")
            }
            RTTChartView(data: chart, domain: now.addingTimeInterval(-selectedSeconds)...now,
                         includeThresholds: includeThresholds, config: config)
                .frame(height: 164)
            HStack {
                Text("\(summary.count) probes in selected range")
                Spacer()
                Text("Min \(fmt(summary.min)) ms")
            }
            .font(.caption2).foregroundStyle(.secondary)
            Divider()
            HStack {
                Text("Recent probes").font(.subheadline.weight(.semibold))
                Spacer()
                Text("Latest 50").font(.caption2).foregroundStyle(.secondary)
            }
            logList
            Divider()
            HStack(spacing: 10) {
                Button("Settings…", action: openSettings).keyboardShortcut(",")
                Spacer()
                Button(action: monitor.togglePause) {
                    Label(monitor.isPaused ? "Resume" : "Pause", systemImage: monitor.isPaused ? "play.fill" : "pause.fill")
                }
                Menu {
                    Button(copied ? "Copied diagnostics" : "Copy diagnostics", action: copyDiagnostics)
                    Button("Export diagnostics…", action: exportDiagnostics)
                    Divider()
                    Button("Quit Pingacik") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: copied ? "checkmark" : "ellipsis") }
                .menuStyle(.borderlessButton).frame(width: 24)
                .help("Diagnostics and Quit")
                .accessibilityLabel("Diagnostics and Quit")
            }
            .controlSize(.small)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "network").foregroundStyle(.secondary)
            Text(monitor.host).font(.headline).lineLimit(1).truncationMode(.middle).help(monitor.host)
            Spacer(minLength: 4)
            Label(monitor.statusText, systemImage: monitor.isNeutral ? (monitor.isPaused ? "pause.circle" : "clock") : (monitor.displayStatus == .ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"))
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(statusColor.opacity(0.1), in: Capsule())
        }
    }

    private func metric(_ name: String, value: String, unit: String) -> some View {
        VStack(spacing: 4) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(.title3, design: .rounded).weight(.semibold)).monospacedDigit()
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var logList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(monitor.recentLog) { sample in
                    let severity = sampleStatus(sample, thresholds: config.thresholds)
                    HStack(spacing: 8) {
                        Image(systemName: !sample.ok ? "xmark.circle.fill" : severity == .ok ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(config.color(for: severity)).frame(width: 12)
                        Text(sample.t, format: .dateTime.hour().minute().second())
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(sample.ok ? "\(fmt(sample.rtt)) ms" : sample.failure?.rawValue ?? "No reply")
                            .foregroundStyle(sample.ok && severity == .ok ? Color.primary : config.color(for: severity))
                    }
                    .font(.system(.caption, design: .monospaced))
                    .help(sample.diagnostic ?? (sample.ok ? "Reply" : sample.failure?.rawValue ?? "No reply"))
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(height: 90)
        .overlay {
            if monitor.samples.isEmpty { Text("Measurements will appear here.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func fmt(_ value: Double) -> String { value >= 0 ? String(format: "%.1f", value) : "—" }

    private var report: String {
        diagnosticReport(target: monitor.target, samples: monitor.samples, status: monitor.statusText)
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        copied = true
    }

    private func exportDiagnostics() {
        let snapshot = report
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Pingacik-diagnostics.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do { try snapshot.write(to: url, atomically: true, encoding: .utf8) }
            catch { exportError = error.localizedDescription }
        }
    }
}
