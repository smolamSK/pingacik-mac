import Foundation

public func diagnosticReport(target: MonitoringTarget, samples: [PingSample], status: String, now: Date = Date()) -> String {
    let summary = stats(samples)
    let formatter = ISO8601DateFormatter()
    let average = summary.avg >= 0 ? String(format: "%.1f ms", summary.avg) : "—"
    var lines = ["Pingacik diagnostics", "Generated: \(formatter.string(from: now))",
                 "Target: \(target.host)", "Interval: \(target.interval)s · timeout: \(target.timeout)s",
                 "Status: \(status)", "Samples: \(summary.count) · failed probes: \(summary.lost)",
                 "Average RTT: \(average)", "", "Time (UTC)\tRTT (ms)\tResult\tDetail"]
    for sample in samples {
        let detail = (sample.diagnostic ?? "").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
        let rtt = sample.ok ? String(format: "%.3f", sample.rtt) : "—"
        lines.append("\(formatter.string(from: sample.t))\t\(rtt)\t\(sample.failure?.rawValue ?? "Reply")\t\(detail)")
    }
    return lines.joined(separator: "\n") + "\n"
}
