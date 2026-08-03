import XCTest
@testable import PingacikCore

private let cfg = Thresholds(yellowAfter: 2, redAfter: 5, recoverAfter: 5, yellowMs: 150, redMs: 500)

/// Drive the machine with a compact string. Input: '.' = good reply,
/// 'x' = timeout, 'w' = slow (over the warning threshold), 'c' = very slow
/// (over the critical one). Output: O = OK, W = Warning, C = Critical.
private func drive(_ seq: String, _ cfg: Thresholds = cfg) -> String {
    var machine = PingStateMachine()
    var out = ""
    for ch in seq {
        let sample: PingSample
        switch ch {
        case "x": sample = PingSample(ok: false, rtt: -1, t: .distantPast)
        case "w": sample = PingSample(ok: true, rtt: 200, t: .distantPast)
        case "c": sample = PingSample(ok: true, rtt: 900, t: .distantPast)
        default: sample = PingSample(ok: true, rtt: 20, t: .distantPast)
        }
        let status = machine.advance(with: sample, thresholds: cfg)
        out += ["O", "W", "C"][status.rawValue]
    }
    return out
}

final class PingStateTests: XCTestCase {

    // MARK: - parsePingOutput

    func testReplyParsedAsOk() {
        let okOut = """
        PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.
        64 bytes from 8.8.8.8: icmp_seq=1 ttl=106 time=20.0 ms

        --- 8.8.8.8 ping statistics ---
        1 packets transmitted, 1 received, 0% packet loss, time 0ms
        """
        let a = parsePingOutput(okOut, exitCode: 0, timestamp: .distantPast)
        XCTAssertTrue(a.ok)
        XCTAssertEqual(a.rtt, 20.0)
    }

    func testTimeoutParsedAsLoss() {
        let failOut = """
        PING 192.0.2.1 (192.0.2.1) 56(84) bytes of data.

        --- 192.0.2.1 ping statistics ---
        1 packets transmitted, 0 received, 100% packet loss, time 0ms
        """
        XCTAssertFalse(parsePingOutput(failOut, exitCode: 1, timestamp: .distantPast).ok)
    }

    func testExitCodeWinsOverStrayRtt() {
        XCTAssertFalse(parsePingOutput("time=5 ms", exitCode: 1, timestamp: .distantPast).ok)
    }

    func testMissingRttIsALoss() {
        XCTAssertFalse(parsePingOutput("nothing here", exitCode: 0, timestamp: .distantPast).ok)
    }

    func testTimeLessThanFormParsed() {
        XCTAssertEqual(parsePingOutput("time<1 ms", exitCode: 0, timestamp: .distantPast).rtt, 1)
    }

    // MARK: - classify

    func testClassify() {
        XCTAssertEqual(classify(PingSample(ok: true, rtt: 20, t: .distantPast), cfg), .good)
        XCTAssertEqual(classify(PingSample(ok: true, rtt: 150, t: .distantPast), cfg), .good)
        XCTAssertEqual(classify(PingSample(ok: true, rtt: 151, t: .distantPast), cfg), .slowWarning)
        XCTAssertEqual(classify(PingSample(ok: true, rtt: 501, t: .distantPast), cfg), .slowCritical)
        XCTAssertEqual(classify(PingSample(ok: false, rtt: -1, t: .distantPast), cfg), .lost)
    }

    // MARK: - hysteresis: loss

    func testAllGoodStaysOk() {
        XCTAssertEqual(drive(".......", cfg), "OOOOOOO")
    }

    func testOneLossNotEnoughForWarning() {
        XCTAssertEqual(drive("..x..", cfg), "OOOOO")
    }

    func testTwoConsecutiveLossesToWarning() {
        XCTAssertEqual(drive("..xx", cfg), "OOOW")
    }

    func testFiveConsecutiveLossesToCritical() {
        XCTAssertEqual(drive("xxxxx", cfg), "OWWWC")
    }

    func testSingleSuccessDoesNotClearWarning() {
        XCTAssertEqual(drive("..xx.", cfg), "OOOWW")
    }

    func testRecoversOnlyOnFifthGoodSample() {
        XCTAssertEqual(drive("..xx.....", cfg), "OOOWWWWWO")
    }

    func testLossDuringRecoveryRestartsCount() {
        XCTAssertEqual(drive("..xx...x.....", cfg), "OOOWWWWWWWWWO")
    }

    // MARK: - hysteresis: latency

    func testTwoSlowSamplesToWarning() {
        XCTAssertEqual(drive("..ww", cfg), "OOOW")
    }

    func testSlowRampsWarningThenCritical() {
        XCTAssertEqual(drive("ccccc", cfg), "OWWWC")
    }

    func testOneSlowSampleIsTolerated() {
        XCTAssertEqual(drive("..w..", cfg), "OOOOO")
    }

    func testSlowRecoveryHonoursRecoverAfter() {
        XCTAssertEqual(drive("..ww.....", cfg), "OOOWWWWWO")
    }

    func testLatencyDegradesWithoutAnyLoss() {
        XCTAssertTrue(drive("wwwww", cfg).contains("W"))
    }

    // MARK: - hysteresis: worst-of

    func testMixedDegradationHolds() {
        XCTAssertEqual(drive("..xxww", cfg), "OOOWWW")
    }

    // MARK: - nextDelay (sample cadence)

    func testFastReplyWaitsOutTheRemainder() {
        XCTAssertEqual(nextDelay(intervalMs: 1000, elapsedMs: 20, minGapMs: 50), 980)
    }

    func testSlowerReplyWaitsLess() {
        XCTAssertEqual(nextDelay(intervalMs: 1000, elapsedMs: 300, minGapMs: 50), 700)
    }

    func testCadenceIsExactlyTheInterval() {
        for rtt in [5.0, 20, 300, 800, 950] {
            XCTAssertEqual(rtt + nextDelay(intervalMs: 1000, elapsedMs: rtt, minGapMs: 50), 1000)
        }
    }

    func testPingThatUsedWholeIntervalRetriesAfterMinGap() {
        XCTAssertEqual(nextDelay(intervalMs: 1000, elapsedMs: 1000, minGapMs: 50), 50)
    }

    func testOutageCadenceIsTimeoutPlusMinGap() {
        XCTAssertEqual(1000 + nextDelay(intervalMs: 1000, elapsedMs: 1000, minGapMs: 50), 1050)
    }

    func testOverrunningPingStillGetsAGap() {
        XCTAssertEqual(nextDelay(intervalMs: 1000, elapsedMs: 5000, minGapMs: 50), 50)
    }

    func testDelayIsNeverBelowTheMinimumGap() {
        for elapsed in [0.0, 999, 1000, 1001, 60000] {
            XCTAssertGreaterThanOrEqual(nextDelay(intervalMs: 1000, elapsedMs: elapsed, minGapMs: 50), 50)
        }
    }

    // MARK: - ring buffer

    func testRingBuffer() {
        var buf: [PingSample] = []
        for i in 0..<10 {
            pushSample(&buf, PingSample(ok: true, rtt: Double(i), t: Date(timeIntervalSince1970: Double(i))), cap: 5)
        }
        XCTAssertEqual(buf.count, 5)
        XCTAssertEqual(buf[4].rtt, 9)
        XCTAssertEqual(buf[0].rtt, 5)
    }

    // MARK: - windowSlice

    func testWindowSlice() {
        var buf: [PingSample] = []
        for i in 0..<100 {
            buf.append(PingSample(ok: true, rtt: 1, t: Date(timeIntervalSince1970: Double(i))))
        }
        let now = Date(timeIntervalSince1970: 99)
        XCTAssertEqual(windowSlice(buf, seconds: 10, now: now).count, 11)
        XCTAssertEqual(windowSlice(buf, seconds: 100_000, now: now).count, 100)
    }

    // MARK: - downsample

    func testDownsampleUnderTargetPassesThrough() {
        var small: [PingSample] = []
        for i in 0..<50 {
            small.append(PingSample(ok: true, rtt: Double(i), t: Date(timeIntervalSince1970: Double(i))))
        }
        XCTAssertEqual(downsample(small, targetPoints: 300).count, 50)
    }

    func testDownsampleToTarget() {
        var big: [PingSample] = []
        for i in 0..<3600 {
            big.append(PingSample(ok: i % 100 != 0, rtt: 20, t: Date(timeIntervalSince1970: Double(i))))
        }
        let ds = downsample(big, targetPoints: 300)
        XCTAssertEqual(ds.count, 300)
        XCTAssertEqual(ds.reduce(0) { $0 + $1.total }, 3600)
        XCTAssertEqual(ds.reduce(0) { $0 + $1.lossCount }, 36)
        XCTAssertTrue(ds.allSatisfy { $0.avg == 20 || $0.avg == -1 })
    }

    func testDownsampleEmptyInput() {
        XCTAssertEqual(downsample([PingSample](), targetPoints: 300).count, 0)
    }

    func testDownsampleAllLostYieldsNegativeOneNotNaN() {
        var allLost: [PingSample] = []
        for i in 0..<600 {
            allLost.append(PingSample(ok: false, rtt: -1, t: Date(timeIntervalSince1970: Double(i))))
        }
        XCTAssertTrue(downsample(allLost, targetPoints: 300).allSatisfy { $0.avg == -1 && $0.min == -1 && $0.max == -1 })
    }

    // MARK: - stats

    func testStats() {
        let s = stats([
            PingSample(ok: true, rtt: 10, t: .distantPast),
            PingSample(ok: true, rtt: 30, t: .distantPast),
            PingSample(ok: false, rtt: -1, t: .distantPast),
            PingSample(ok: true, rtt: 20, t: .distantPast)
        ])
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s.received, 3)
        XCTAssertEqual(s.lost, 1)
        XCTAssertEqual(s.lossPercent, 25)
        XCTAssertEqual(s.avg, 20)
        XCTAssertEqual(s.min, 10)
        XCTAssertEqual(s.max, 30)
    }

    func testStatsEmpty() {
        let empty = stats([PingSample]())
        XCTAssertEqual(empty.avg, -1)
        XCTAssertEqual(empty.lossPercent, 0)
    }
}
