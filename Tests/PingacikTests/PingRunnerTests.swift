import XCTest
import PingacikCore
@testable import Pingacik

final class PingRunnerTests: XCTestCase {
    func testRealPingToLoopbackDeliversSessionAndTiming() async {
        let runner = PingRunner()
        let token = UUID()
        let received = expectation(description: "Loopback reply")
        runner.onSample = { sample, session in
            XCTAssertEqual(session, token)
            XCTAssertTrue(sample.ok, sample.diagnostic ?? sample.failure?.rawValue ?? "No reply")
            XCTAssertGreaterThanOrEqual(sample.rtt, 0)
            XCTAssertLessThanOrEqual(sample.startedAt, sample.t)
            XCTAssertTrue(Thread.isMainThread)
            received.fulfill()
        }
        runner.start(target: MonitoringTarget(host: "127.0.0.1", interval: 60, timeout: 1), session: token)
        await fulfillment(of: [received], timeout: 5)
        runner.stop()
    }
}
