import Foundation
import PingacikCore

/// Runs `ping` against a host on an interval, one process in flight at a
/// time, and hands each parsed result back via `onSample`.
///
/// Port of `main.qml`'s sampler: the next ping is scheduled from when the
/// *previous one started* (not when it finished) so the cadence holds at
/// `pingInterval` regardless of round-trip time, and a watchdog force-
/// completes the sample if the process never reports back at all.
///
/// All mutable state is confined to `queue`; `onSample` is always delivered
/// on the main queue since it feeds an `ObservableObject`.
final class PingRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "pingacik.pingrunner")

    private var host: String
    private var intervalMs: Double
    private var timeoutMs: Double
    private let minGapMs: Double = 50

    private var process: Process?
    private var busy = false
    private var lastStart = Date.distantPast
    private var watchdogWorkItem: DispatchWorkItem?
    private var scheduledWorkItem: DispatchWorkItem?
    private var generation = 0

    var onSample: (@Sendable (PingSample) -> Void)?

    init(host: String, pingIntervalSeconds: Int, pingTimeoutSeconds: Int) {
        self.host = host
        self.intervalMs = Double(pingIntervalSeconds) * 1000
        self.timeoutMs = Double(pingTimeoutSeconds) * 1000
    }

    /// (Re)start sampling with the current target. Cancels any in-flight
    /// ping so its result can't be attributed to a target that's already
    /// changed.
    func start() {
        queue.async { self.restartLocked() }
    }

    func stop() {
        queue.async { self.stopLocked() }
    }

    /// Changing what or how we measure invalidates any in-flight ping and
    /// restarts sampling, mirroring `onHostChanged`/`onPingIntervalChanged`/
    /// `onPingTimeoutChanged` in `main.qml`.
    func updateTarget(host: String, pingIntervalSeconds: Int, pingTimeoutSeconds: Int) {
        queue.async {
            self.host = host
            self.intervalMs = Double(pingIntervalSeconds) * 1000
            self.timeoutMs = Double(pingTimeoutSeconds) * 1000
            self.restartLocked()
        }
    }

    // MARK: - Queue-confined implementation

    private func restartLocked() {
        stopLocked()
        doPing()
    }

    private func stopLocked() {
        generation += 1 // invalidate any in-flight callbacks
        scheduledWorkItem?.cancel()
        watchdogWorkItem?.cancel()
        scheduledWorkItem = nil
        watchdogWorkItem = nil
        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }
        process = nil
        busy = false
    }

    private func doPing() {
        guard !busy else { return }
        busy = true
        lastStart = Date()
        let myGeneration = generation

        let watchdogItem = DispatchWorkItem { [weak self] in
            self?.queue.async { self?.handleWatchdogFired(generation: myGeneration) }
        }
        watchdogWorkItem = watchdogItem
        queue.asyncAfter(deadline: .now() + (timeoutMs / 1000) + 5, execute: watchdogItem)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/sbin/ping")
        proc.arguments = ["-n", "-c", "1", "-W", String(Int(timeoutMs)), host]
        proc.environment = ["LC_ALL": "C"]

        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = Pipe()

        process = proc

        proc.terminationHandler = { [weak self] finished in
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: data, encoding: .utf8)
            let exitCode = finished.terminationStatus
            self?.queue.async {
                self?.handleProcessFinished(stdout: stdout, exitCode: exitCode, generation: myGeneration)
            }
        }

        do {
            try proc.run()
        } catch {
            queue.async { [weak self] in
                self?.handleProcessFinished(stdout: nil, exitCode: -1, generation: myGeneration)
            }
        }
    }

    private func handleProcessFinished(stdout: String?, exitCode: Int32, generation: Int) {
        // Dropped by the watchdog already, or superseded by a restart:
        // ignore the late arrival rather than attributing it to a request
        // that's no longer outstanding.
        guard generation == self.generation, busy else { return }
        busy = false
        watchdogWorkItem?.cancel()
        watchdogWorkItem = nil
        process = nil

        let sample = parsePingOutput(stdout, exitCode: exitCode, timestamp: Date())
        deliver(sample)
        scheduleNext()
    }

    private func handleWatchdogFired(generation: Int) {
        guard generation == self.generation, busy else { return }
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        busy = false
        deliver(PingSample(ok: false, rtt: -1, t: Date()))
        scheduleNext()
    }

    private func scheduleNext() {
        let elapsedMs = Date().timeIntervalSince(lastStart) * 1000
        let delayMs = nextDelay(intervalMs: intervalMs, elapsedMs: elapsedMs, minGapMs: minGapMs)
        let myGeneration = generation
        let item = DispatchWorkItem { [weak self] in
            self?.queue.async {
                guard self?.generation == myGeneration else { return }
                self?.doPing()
            }
        }
        scheduledWorkItem = item
        queue.asyncAfter(deadline: .now() + delayMs / 1000, execute: item)
    }

    private func deliver(_ sample: PingSample) {
        let handler = onSample
        DispatchQueue.main.async { handler?(sample) }
    }
}
