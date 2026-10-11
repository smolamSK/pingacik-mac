import XCTest
@testable import PingacikCore

final class MonitoringTests: XCTestCase {
    func testHostValidation() {
        XCTAssertEqual(MonitoringTarget.normalizedHost(" Example.COM \n"), "example.com")
        for host in ["8.8.8.8", "localhost", "my-router.local", "example.com."] {
            XCTAssertNotNil(MonitoringTarget.normalizedHost(host), host)
        }
        for host in ["", " ", "-bad", "bad-", "foo..com", "https://example.com", "host:443", "256.1.1.1", "8.8.8", "a b", "::1", "a/b", String(repeating: "a", count: 64) + ".com"] {
            XCTAssertNil(MonitoringTarget.normalizedHost(host), host)
        }
    }

    func testFailureReasons() {
        XCTAssertEqual(parsePingOutput(nil, exitCode: 68, timestamp: .now, stderr: "ping: cannot resolve example.invalid: Unknown host").failure, .dns)
        XCTAssertEqual(parsePingOutput(nil, exitCode: 2, timestamp: .now, stderr: "ping: sendto: No route to host").failure, .unreachable)
        XCTAssertEqual(parsePingOutput(nil, exitCode: -1, timestamp: .now, stderr: "Permission denied").failure, .launch)
        XCTAssertEqual(parsePingOutput(nil, exitCode: 2, timestamp: .now, stderr: "Operation not permitted").failure, .execution)
        XCTAssertEqual(parsePingOutput("", exitCode: 2, timestamp: .now).failure, .timeout)
        XCTAssertEqual(parsePingOutput("no RTT", exitCode: 0, timestamp: .now).failure, .invalidReply)
        XCTAssertNil(parsePingOutput("time=12.3 ms", exitCode: 0, timestamp: .now).failure)
    }

    func testSeverityIncludesSlowSuccessfulReplies() {
        let cfg = Thresholds(yellowAfter: 2, redAfter: 5, recoverAfter: 5, yellowMs: 150, redMs: 500)
        XCTAssertEqual(sampleStatus(PingSample(ok: true, rtt: 200, t: .now), thresholds: cfg), .warning)
        XCTAssertEqual(sampleStatus(PingSample(ok: true, rtt: 700, t: .now), thresholds: cfg), .critical)
    }

    private func sample(_ second: Double, ok: Bool = true) -> PingSample {
        PingSample(ok: ok, rtt: ok ? 20 : -1, t: Date(timeIntervalSince1970: second + 1),
                   startedAt: Date(timeIntervalSince1970: second))
    }

    func testChartBreaksAcrossLossEvenWhenDownsampled() {
        let samples = (0..<600).map { sample(Double($0), ok: $0 != 300) }
        let chart = ChartData(samples: samples, interval: 1, timeout: 1, targetPoints: 10)
        XCTAssertEqual(Set(chart.points.map(\.segment)).count, 2)
        XCTAssertEqual(chart.losses.count, 1)
        XCTAssertEqual(chart.losses[0].start, samples[300].startedAt)
        XCTAssertEqual(chart.losses[0].end, samples[300].t)
        XCTAssertLessThanOrEqual(chart.points.count, 12)
    }

    func testChartBreaksAcrossSleepAndSessions() {
        let chart = ChartData(samples: [sample(0), sample(1), sample(100)], interval: 1, timeout: 1)
        XCTAssertEqual(chart.points.map(\.segment), [0, 0, 1])
        var first = sample(0)
        var second = sample(1)
        first.sessionID = UUID()
        second.sessionID = UUID()
        let resumed = ChartData(samples: [first, second], interval: 1, timeout: 1)
        XCTAssertEqual(resumed.points.map(\.segment), [0, 1])
    }

    func testChartScaleAndEmptyData() {
        let chart = ChartData(samples: [sample(0)], interval: 1, timeout: 1)
        XCTAssertEqual(chart.upperBound(criticalThreshold: 500, includeThresholds: false), 24)
        XCTAssertEqual(chart.upperBound(criticalThreshold: 500, includeThresholds: true), 600)
        let empty = ChartData(samples: [], interval: 1, timeout: 1)
        XCTAssertEqual(empty.upperBound(criticalThreshold: 500, includeThresholds: false), 10)
        XCTAssertTrue(empty.points.isEmpty)
        let losses = ChartData(samples: [sample(0, ok: false)], interval: 1, timeout: 1)
        XCTAssertTrue(losses.points.isEmpty)
        XCTAssertEqual(losses.losses.count, 1)
    }

    func testDiagnosticReportContainsTargetAndFailures() {
        let samples = [sample(0), PingSample(ok: false, rtt: -1, t: .distantPast, failure: .dns, diagnostic: "unknown\nhost")]
        let report = diagnosticReport(target: MonitoringTarget(host: "example.com", interval: 2, timeout: 3), samples: samples, status: "Warning")
        XCTAssertTrue(report.contains("Target: example.com"))
        XCTAssertTrue(report.contains("failed probes: 1"))
        XCTAssertTrue(report.contains("Host not found\tunknown host"))
        XCTAssertTrue(report.contains("Average RTT: 20.0 ms"))
    }
}
