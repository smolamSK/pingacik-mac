import Foundation
import Combine
import PingacikCore

/// Wires `Config`, `PingRunner` and the hysteresis state machine together,
/// publishing the live values the menu bar UI observes. Mirrors the root
/// properties of `main.qml`.
@MainActor
final class PingMonitor: ObservableObject {
    private let config: Config
    private let runner: PingRunner
    private var machine = PingStateMachine()
    private var cancellables = Set<AnyCancellable>()

    private let bufferCap = 3600 // 1 h at 1 s
    let logCap = 500

    @Published private(set) var samples: [PingSample] = []
    @Published private(set) var connectionStatus: ConnectionStatus = .ok
    @Published private(set) var lastRtt: Double = -1
    @Published private(set) var lastOk = false
    @Published private(set) var sampleCount = 0
    @Published private(set) var avgRtt: Double = -1
    @Published private(set) var minRtt: Double = -1
    @Published private(set) var maxRtt: Double = -1
    @Published private(set) var lossPercent: Double = 0

    /// The most recent samples, newest first, for the log list.
    var recentLog: [PingSample] {
        Array(samples.suffix(logCap).reversed())
    }

    var host: String { config.host }

    init(config: Config) {
        self.config = config
        self.runner = PingRunner(
            host: config.host,
            pingIntervalSeconds: config.pingInterval,
            pingTimeoutSeconds: config.pingTimeout
        )

        runner.onSample = { [weak self] sample in
            // PingRunner always delivers on the main queue.
            MainActor.assumeIsolated {
                self?.recordSample(sample)
            }
        }

        // Changing what or how we measure invalidates the history, same as
        // onHostChanged/onPingIntervalChanged/onPingTimeoutChanged in main.qml.
        Publishers.Merge3(
            config.$host.dropFirst().map { _ in () },
            config.$pingInterval.dropFirst().map { _ in () },
            config.$pingTimeout.dropFirst().map { _ in () }
        )
        .sink { [weak self] in self?.restartSampler() }
        .store(in: &cancellables)

        runner.start()
    }

    /// Buckets covering the last `seconds`, downsampled for the chart.
    func buckets(overLast seconds: Double, targetPoints: Int = 300) -> [RTTBucket] {
        downsample(windowSlice(samples, seconds: seconds, now: Date()), targetPoints: targetPoints)
    }

    /// Aggregate stats over the last `seconds`, for the popup header.
    func stats(overLast seconds: Double) -> PingStats {
        PingacikCore.stats(windowSlice(samples, seconds: seconds, now: Date()))
    }

    private func restartSampler() {
        resetHistory()
        runner.updateTarget(
            host: config.host,
            pingIntervalSeconds: config.pingInterval,
            pingTimeoutSeconds: config.pingTimeout
        )
    }

    private func resetHistory() {
        samples = []
        machine = PingStateMachine()
        connectionStatus = .ok
        lastRtt = -1
        lastOk = false
        sampleCount = 0
        avgRtt = -1
        minRtt = -1
        maxRtt = -1
        lossPercent = 0
    }

    private func recordSample(_ sample: PingSample) {
        pushSample(&samples, sample, cap: bufferCap)
        connectionStatus = machine.advance(with: sample, thresholds: config.thresholds)
        lastOk = sample.ok
        lastRtt = sample.rtt
        sampleCount = samples.count

        let s = PingacikCore.stats(samples)
        avgRtt = s.avg
        minRtt = s.min
        maxRtt = s.max
        lossPercent = s.lossPercent
    }
}
