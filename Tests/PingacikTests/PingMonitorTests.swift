import XCTest
import PingacikCore
@testable import Pingacik

final class FakePingRunner: PingRunning {
    var onSample: (@Sendable (PingSample, UUID) -> Void)?
    var starts: [(MonitoringTarget, UUID)] = []
    var stopCount = 0
    func start(target: MonitoringTarget, session: UUID) { starts.append((target, session)) }
    func stop() { stopCount += 1 }
    func reply(ok: Bool = true, rtt: Double = 20, token: UUID? = nil, failure: PingFailure? = nil) {
        onSample?(PingSample(ok: ok, rtt: ok ? rtt : -1, t: Date(), failure: failure), token ?? starts.last!.1)
    }
}

final class PingMonitorTests: XCTestCase {
    @MainActor
    private func withMonitor(_ body: (Config, PingMonitor, FakePingRunner) -> Void) {
        let name = "PingacikTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let config = Config(defaults: defaults)
        let runner = FakePingRunner()
        let monitor = PingMonitor(config: config, runner: runner, observeLifecycle: false)
        defer { monitor.shutdown() }
        body(config, monitor, runner)
    }

    func testNewHostIsUsedImmediatelyAndHistoryResets() async {
        await MainActor.run {
            withMonitor { config, monitor, runner in
                runner.reply()
                config.host = "1.1.1.1"
                XCTAssertEqual(runner.starts.last?.0.host, "1.1.1.1")
                XCTAssertEqual(monitor.host, "1.1.1.1")
                XCTAssertEqual(monitor.sampleCount, 0)
                XCTAssertEqual(monitor.activity, .checking)
            }
        }
    }

    func testTimingChangesUseNewValuesAndKeepOtherSettings() async {
        await MainActor.run {
            withMonitor { config, _, runner in
                config.pingInterval = 5
                XCTAssertEqual(runner.starts.last?.0.interval, 5)
                config.pingTimeout = 3
                XCTAssertEqual(runner.starts.last?.0, MonitoringTarget(host: "8.8.8.8", interval: 5, timeout: 3))
                let count = runner.starts.count
                config.pingTimeout = 3
                XCTAssertEqual(runner.starts.count, count)
            }
        }
    }

    func testLateResultFromPreviousTargetIsRejected() async {
        await MainActor.run {
            withMonitor { config, monitor, runner in
                let oldToken = runner.starts.last!.1
                config.host = "example.com"
                runner.reply(token: oldToken)
                XCTAssertTrue(monitor.samples.isEmpty)
                runner.reply()
                XCTAssertEqual(monitor.sampleCount, 1)
            }
        }
    }

    func testPausePreservesHistoryAndResumeRequiresFreshReply() async {
        await MainActor.run {
            withMonitor { _, monitor, runner in
                runner.reply()
                let oldToken = runner.starts.last!.1
                monitor.togglePause()
                runner.reply(token: oldToken)
                XCTAssertEqual(monitor.sampleCount, 1)
                XCTAssertEqual(monitor.activity, .paused)
                monitor.togglePause()
                XCTAssertEqual(monitor.activity, .checking)
                runner.reply(token: oldToken)
                XCTAssertEqual(monitor.sampleCount, 1)
                runner.reply()
                XCTAssertEqual(monitor.activity, .live)
                XCTAssertEqual(monitor.sampleCount, 2)
                XCTAssertNotEqual(monitor.samples[0].sessionID, monitor.samples[1].sessionID)
            }
        }
    }

    func testSettingsWhilePausedDoNotStartPings() async {
        await MainActor.run {
            withMonitor { config, monitor, runner in
                monitor.togglePause()
                let count = runner.starts.count
                config.host = "example.com"
                XCTAssertEqual(runner.starts.count, count)
                XCTAssertEqual(monitor.activity, .paused)
                monitor.togglePause()
                XCTAssertEqual(runner.starts.last?.0.host, "example.com")
            }
        }
    }

    func testSleepWakeAndStaleness() async {
        await MainActor.run {
            withMonitor { _, monitor, runner in
                XCTAssertTrue(monitor.isNeutral)
                runner.reply()
                monitor.checkFreshness(now: Date().addingTimeInterval(20))
                XCTAssertEqual(monitor.activity, .stale)
                monitor.prepareForSleep()
                let oldToken = runner.starts.last!.1
                runner.reply(token: oldToken)
                XCTAssertEqual(monitor.sampleCount, 1)
                monitor.wake()
                XCTAssertEqual(monitor.activity, .checking)
                runner.reply()
                XCTAssertEqual(monitor.activity, .live)
                monitor.togglePause()
                let count = runner.starts.count
                monitor.prepareForSleep()
                monitor.wake()
                XCTAssertEqual(runner.starts.count, count)
                XCTAssertEqual(monitor.activity, .paused)
            }
        }
    }

    func testRecoveryAndFailureLabels() async {
        await MainActor.run {
            withMonitor { _, monitor, runner in
                runner.reply(ok: false, failure: .dns)
                XCTAssertEqual(monitor.statusText, "Check target")
                XCTAssertEqual(monitor.statusDetail, "Host not found")
                runner.reply(ok: false)
                XCTAssertEqual(monitor.connectionStatus, .warning)
                runner.reply()
                XCTAssertEqual(monitor.statusText, "Recovering")
                XCTAssertEqual(monitor.statusDetail, "1 of 5 good replies to recover")
                for _ in 0..<4 { runner.reply() }
                XCTAssertEqual(monitor.statusText, "OK")
            }
        }
    }

    func testInvalidSavedSettingsAreNormalized() async {
        await MainActor.run {
            let name = "PingacikTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: name)!
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set("-bad host", forKey: "host")
            defaults.set(0, forKey: "pingInterval")
            defaults.set(100, forKey: "yellowAfter")
            defaults.set(1, forKey: "redAfter")
            defaults.set(10001, forKey: "yellowMs")
            defaults.set(3, forKey: "redMs")
            defaults.set(7, forKey: "defaultTimescale")
            let config = Config(defaults: defaults)
            XCTAssertEqual(config.host, "8.8.8.8")
            XCTAssertEqual(config.pingInterval, 1)
            XCTAssertGreaterThan(config.redAfter, config.yellowAfter)
            XCTAssertGreaterThan(config.redMs, config.yellowMs)
            XCTAssertEqual(config.defaultTimescale, 300)
        }
    }
}
