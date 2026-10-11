import Foundation
import PingacikCore

protocol PingRunning: AnyObject {
    var onSample: (@Sendable (PingSample, UUID) -> Void)? { get set }
    func start(target: MonitoringTarget, session: UUID)
    func stop()
}

/// Mutable process state stays on a serial queue; samples are delivered on the main queue.
final class PingRunner: PingRunning, @unchecked Sendable {
    private let queue = DispatchQueue(label: "pingacik.pingrunner")
    private var target = MonitoringTarget(host: "8.8.8.8", interval: 1, timeout: 1)
    private var session = UUID()
    private var request: UUID?
    private var process: Process?
    private var startedAt = Date()
    private var startedClock = DispatchTime.now()
    private var watchdog: DispatchWorkItem?
    private var scheduled: DispatchWorkItem?
    private var handler: (@Sendable (PingSample, UUID) -> Void)?

    // Set before starting. Each start captures its callback for the worker queue.
    var onSample: (@Sendable (PingSample, UUID) -> Void)?

    func start(target: MonitoringTarget, session: UUID) {
        let callback = onSample
        queue.async {
            self.stopLocked()
            self.target = target
            self.session = session
            self.handler = callback
            self.doPing()
        }
    }

    func stop() { queue.async { self.stopLocked() } }

    private func stopLocked() {
        request = nil
        session = UUID()
        scheduled?.cancel()
        watchdog?.cancel()
        scheduled = nil
        watchdog = nil
        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }
        process = nil
    }

    private func doPing() {
        guard request == nil else { return }
        let requestID = UUID()
        request = requestID
        startedAt = Date()
        startedClock = .now()

        let work = DispatchWorkItem { [weak self] in self?.timedOut(requestID) }
        watchdog = work
        queue.asyncAfter(deadline: .now() + Double(target.timeout) + 2, execute: work)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/ping")
        // -t bounds the whole command; -W alone only controls reply acceptance on macOS.
        proc.arguments = ["-n", "-c", "1", "-W", String(target.timeout * 1000), "-t", String(target.timeout), target.host]
        proc.environment = ["LC_ALL": "C"]
        let output = Pipe()
        let errors = Pipe()
        proc.standardOutput = output
        proc.standardError = errors
        process = proc
        proc.terminationHandler = { [weak self] finished in
            let stdout = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            let stderr = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            let code = finished.terminationStatus
            self?.queue.async { self?.finished(requestID, stdout: stdout, stderr: stderr, code: code) }
        }
        do { try proc.run() }
        catch { finished(requestID, stdout: nil, stderr: error.localizedDescription, code: -1) }
    }

    private func finished(_ id: UUID, stdout: String?, stderr: String?, code: Int32) {
        guard request == id else { return }
        watchdog?.cancel()
        watchdog = nil
        request = nil
        process = nil
        deliver(parsePingOutput(stdout, exitCode: code, timestamp: Date(), stderr: stderr, startedAt: startedAt))
        scheduleNext()
    }

    private func timedOut(_ id: UUID) {
        guard request == id else { return }
        request = nil
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        watchdog = nil
        deliver(PingSample(ok: false, rtt: -1, t: Date(), startedAt: startedAt, failure: .watchdog))
        scheduleNext()
    }

    private func scheduleNext() {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - startedClock.uptimeNanoseconds) / 1_000_000
        let delay = nextDelay(intervalMs: Double(target.interval * 1000), elapsedMs: elapsed, minGapMs: 50)
        let token = session
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.session == token else { return }
            self.doPing()
        }
        scheduled = item
        queue.asyncAfter(deadline: .now() + delay / 1000, execute: item)
    }

    private func deliver(_ sample: PingSample) {
        let callback = handler
        let token = session
        DispatchQueue.main.async { callback?(sample, token) }
    }
}
