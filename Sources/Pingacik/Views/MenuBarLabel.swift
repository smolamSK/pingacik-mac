import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var monitor: PingMonitor
    @ObservedObject var config: Config

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(monitor.isNeutral ? Color.secondary : config.color(for: monitor.displayStatus))
                .frame(width: 10)
            if config.showLatencyText {
                Text(latencyText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .frame(width: 62, alignment: .trailing)
            }
        }
        .padding(.horizontal, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Pingacik, \(monitor.host), \(monitor.statusText)")
        .accessibilityValue(latencyText)
    }

    private var symbol: String {
        switch monitor.activity {
        case .paused: return "pause.fill"
        case .checking: return "circle.dotted"
        case .stale: return "clock"
        case .live: return monitor.displayStatus == .ok ? "circle.fill" : "exclamationmark.triangle.fill"
        }
    }

    private var latencyText: String {
        guard monitor.activity == .live else { return monitor.isPaused ? "Paused" : "…" }
        guard monitor.lastOk else { return "—" }
        return monitor.lastRtt >= 10000 ? "≥10 s" : "\(Int(monitor.lastRtt.rounded())) ms"
    }
}
