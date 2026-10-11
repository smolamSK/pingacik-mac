import Foundation
import Combine
import AppKit
import PingacikCore

@MainActor
final class PingMonitor: ObservableObject {
    enum Activity: Equatable { case checking, live, paused, stale }

    private let config: Config
    private let runner: PingRunning
    private var machine = PingStateMachine()
    private var cancellables = Set<AnyCancellable>()
    private var session = UUID()
    private var sleeping = false
    private var waitingSince = Date()
    private var awaitingFreshSample = true
    private var stopped = false

    @Published private(set) var target: MonitoringTarget
    @Published private(set) var samples: [PingSample] = []
    @Published private(set) var connectionStatus: ConnectionStatus = .ok
    @Published private(set) var activity: Activity = .checking
    @Published private(set) var isPaused = false
    @Published private(set) var recoveryCount = 0

    var host: String { target.host }
    var latest: PingSample? { samples.last }
    var sampleCount: Int { samples.count }
    var lastRtt: Double { latest?.rtt ?? -1 }
    var lastOk: Bool { latest?.ok ?? false }
    var recentLog: [PingSample] { Array(samples.suffix(50).reversed()) }
    var isNeutral: Bool { activity != .live }

    var statusText: String {
        switch activity {
        case .checking: return "Checking"
        case .paused: return "Paused"
        case .stale: return "No recent data"
        case .live:
            if recoveryCount > 0 && connectionStatus != .ok { return "Recovering" }
            if latest?.failure == .dns || latest?.failure == .launch || latest?.failure == .execution || latest?.failure == .invalidReply {
                return "Check target"
            }
            if connectionStatus == .ok && !lastOk { return "Missed reply" }
            switch connectionStatus {
            case .ok: return "OK"
            case .warning: return "Warning"
            case .critical: return "Critical"
            }
        }
    }

    var statusDetail: String {
        switch activity {
        case .checking: return "Waiting for a fresh measurement…"
        case .paused: return "Monitoring is paused. History is preserved."
        case .stale: return sleeping ? "Waiting for your Mac to wake." : "Measurements are out of date."
        case .live:
            if recoveryCount > 0 && connectionStatus != .ok {
                return "\(recoveryCount) of \(config.recoverAfter) good replies to recover"
            }
            if let failure = latest?.failure { return failure.rawValue }
            return "One probe every \(target.interval)s · timeout \(target.timeout)s"
        }
    }

    var displayStatus: ConnectionStatus {
        if activity == .live, let latest, !latest.ok { return max(connectionStatus, .warning) }
        return connectionStatus
    }

    init(config: Config, runner: PingRunning = PingRunner(), observeLifecycle: Bool = true) {
        self.config = config
        self.runner = runner
        target = MonitoringTarget(host: config.host, interval: config.pingInterval, timeout: config.pingTimeout)
        runner.onSample = { [weak self] sample, token in
            MainActor.assumeIsolated { self?.recordSample(sample, session: token) }
        }

        // Consume published values, which arrive before the properties are stored.
        Publishers.CombineLatest3(config.$host, config.$pingInterval, config.$pingTimeout)
            .map { MonitoringTarget(host: $0, interval: $1, timeout: $2) }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] target in self?.changeTarget(target) }
            .store(in: &cancellables)

        if observeLifecycle {
            let center = NSWorkspace.shared.notificationCenter
            center.publisher(for: NSWorkspace.willSleepNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.prepareForSleep() }
                .store(in: &cancellables)
            center.publisher(for: NSWorkspace.didWakeNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.wake() }
                .store(in: &cancellables)
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
                .sink { [weak self] now in self?.checkFreshness(now: now) }
                .store(in: &cancellables)
        }
        beginSampling()
    }

    func samples(overLast seconds: Double, now: Date = Date()) -> [PingSample] {
        Array(windowSlice(samples, seconds: seconds, now: now))
    }

    func togglePause() {
        isPaused.toggle()
        invalidateSession()
        if isPaused { activity = .paused }
        else if sleeping { activity = .stale }
        else { beginSampling() }
    }

    func prepareForSleep() {
        sleeping = true
        invalidateSession()
        if !isPaused { activity = .stale }
    }

    func wake() {
        sleeping = false
        if !isPaused { beginSampling() }
    }

    func shutdown() {
        stopped = true
        invalidateSession()
        cancellables.removeAll()
    }

    func checkFreshness(now: Date) {
        guard !isPaused, !sleeping, !stopped else { return }
        let reference = awaitingFreshSample ? waitingSince : (latest?.t ?? waitingSince)
        if now.timeIntervalSince(reference) > Double(target.interval + target.timeout + 4) {
            activity = .stale
        }
    }

    private func invalidateSession() {
        session = UUID()
        runner.stop()
    }

    private func changeTarget(_ newTarget: MonitoringTarget) {
        invalidateSession()
        target = newTarget
        samples = []
        machine = PingStateMachine()
        connectionStatus = .ok
        recoveryCount = 0
        if !isPaused && !sleeping { beginSampling() }
    }

    private func beginSampling() {
        guard !stopped else { return }
        session = UUID()
        waitingSince = Date()
        awaitingFreshSample = true
        machine = PingStateMachine()
        connectionStatus = .ok
        recoveryCount = 0
        activity = .checking
        runner.start(target: target, session: session)
    }

    private func recordSample(_ sample: PingSample, session token: UUID) {
        guard token == session, !isPaused, !sleeping, !stopped else { return }
        var sample = sample
        sample.sessionID = token
        if activity == .stale { machine = PingStateMachine() }
        pushSample(&samples, sample, cap: 3600)
        connectionStatus = machine.advance(with: sample, thresholds: config.thresholds)
        recoveryCount = machine.consecutiveGood
        awaitingFreshSample = false
        activity = .live
    }
}
