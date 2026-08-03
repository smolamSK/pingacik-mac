import SwiftUI

/// Compact representation: a status dot plus the live latency, shown in the
/// menu bar itself.
struct MenuBarLabel: View {
    @ObservedObject var monitor: PingMonitor
    @ObservedObject var config: Config

    var body: some View {
        HStack(spacing: 4) {
            StatusDot(status: monitor.connectionStatus, config: config, diameter: 8)
            if config.showLatencyText {
                Text(latencyText)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .padding(.horizontal, 4)
    }

    private var latencyText: String {
        guard monitor.sampleCount > 0 else { return "…" }
        return monitor.lastOk ? "\(Int(monitor.lastRtt.rounded())) ms" : "—"
    }
}
