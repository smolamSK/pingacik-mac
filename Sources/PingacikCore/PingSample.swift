import Foundation

/// A single ping result: either a reply with a round-trip time, or a loss.
public struct PingSample: Sendable, Equatable, Identifiable {
    public let id = UUID()
    public var ok: Bool
    public var rtt: Double // milliseconds; -1 when `ok` is false
    public var t: Date
    public var startedAt: Date
    public var failure: PingFailure?
    public var diagnostic: String?
    public var sessionID: UUID?

    public init(ok: Bool, rtt: Double, t: Date, startedAt: Date? = nil,
                failure: PingFailure? = nil, diagnostic: String? = nil) {
        self.ok = ok
        self.rtt = rtt
        self.t = t
        self.startedAt = startedAt ?? t
        self.failure = ok ? nil : (failure ?? .timeout)
        self.diagnostic = diagnostic
    }
}

public enum PingFailure: String, Sendable {
    case timeout = "No reply"
    case dns = "Host not found"
    case unreachable = "Host unreachable"
    case launch = "Could not start ping"
    case execution = "Ping error"
    case invalidReply = "Unreadable reply"
    case watchdog = "Ping stalled"
}

private let rttPattern = try! NSRegularExpression(pattern: #"time[=<]\s*([\d.]+)\s*ms"#)

/// Parse the output of `ping -n -c 1 -W <ms> <host>`.
/// Success requires a zero exit code *and* an rtt in the output; anything else
/// counts as a lost packet.
public func parsePingOutput(_ stdout: String?, exitCode: Int32, timestamp: Date,
                            stderr: String? = nil, startedAt: Date? = nil) -> PingSample {
    guard exitCode == 0, let stdout else {
        let detail = stderr?.trimmingCharacters(in: .whitespacesAndNewlines)
        let output = ((stdout ?? "") + " " + (detail ?? "")).lowercased()
        let reason: PingFailure
        if exitCode == -1 { reason = .launch }
        else if output.contains("unknown host") || output.contains("cannot resolve") || output.contains("name or service not known") {
            reason = .dns
        } else if output.contains("unreachable") || output.contains("no route to host") || output.contains("network is down") {
            reason = .unreachable
        } else if let detail, !detail.isEmpty { reason = .execution }
        else { reason = .timeout }
        return PingSample(ok: false, rtt: -1, t: timestamp, startedAt: startedAt,
                          failure: reason, diagnostic: detail?.isEmpty == false ? detail : nil)
    }
    let range = NSRange(stdout.startIndex..<stdout.endIndex, in: stdout)
    guard let match = rttPattern.firstMatch(in: stdout, range: range),
          let rttRange = Range(match.range(at: 1), in: stdout),
          let rtt = Double(stdout[rttRange]) else {
        return PingSample(ok: false, rtt: -1, t: timestamp, startedAt: startedAt, failure: .invalidReply)
    }
    return PingSample(ok: true, rtt: rtt, t: timestamp, startedAt: startedAt)
}
