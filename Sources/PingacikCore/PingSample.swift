import Foundation

/// A single ping result: either a reply with a round-trip time, or a loss.
public struct PingSample: Sendable, Equatable {
    public var ok: Bool
    public var rtt: Double // milliseconds; -1 when `ok` is false
    public var t: Date

    public init(ok: Bool, rtt: Double, t: Date) {
        self.ok = ok
        self.rtt = rtt
        self.t = t
    }
}

private let rttPattern = try! NSRegularExpression(pattern: #"time[=<]\s*([\d.]+)\s*ms"#)

/// Parse the output of `ping -n -c 1 -W <ms> <host>`.
/// Success requires a zero exit code *and* an rtt in the output; anything else
/// counts as a lost packet.
public func parsePingOutput(_ stdout: String?, exitCode: Int32, timestamp: Date) -> PingSample {
    guard exitCode == 0, let stdout else {
        return PingSample(ok: false, rtt: -1, t: timestamp)
    }
    let range = NSRange(stdout.startIndex..<stdout.endIndex, in: stdout)
    guard let match = rttPattern.firstMatch(in: stdout, range: range),
          let rttRange = Range(match.range(at: 1), in: stdout),
          let rtt = Double(stdout[rttRange]) else {
        return PingSample(ok: false, rtt: -1, t: timestamp)
    }
    return PingSample(ok: true, rtt: rtt, t: timestamp)
}
