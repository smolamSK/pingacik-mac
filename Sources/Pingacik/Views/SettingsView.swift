import SwiftUI
import PingacikCore

struct SettingsView: View {
    @ObservedObject var config: Config
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings category", selection: $selectedTab) {
                Text("General").tag(0)
                Text("Appearance").tag(1)
                Text("Thresholds").tag(2)
            }
            .pickerStyle(.segmented).labelsHidden().padding(16)
            switch selectedTab {
            case 1: AppearanceSettingsView(config: config)
            case 2: ThresholdsSettingsView(config: config)
            default: GeneralSettingsView(config: config)
            }
        }
        .frame(width: 480, height: 460)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var config: Config
    @State private var draftHost = ""
    @StateObject private var loginItem = LoginItem()
    private var normalizedHost: String? { MonitoringTarget.normalizedHost(draftHost) }

    var body: some View {
        Form {
            Section("Target") {
                HStack {
                    TextField("Host", text: $draftHost, prompt: Text("8.8.8.8 or example.com"))
                        .onSubmit(applyHost)
                        .autocorrectionDisabled()
                    Button("Apply", action: applyHost)
                        .disabled(normalizedHost == nil || normalizedHost == config.host)
                }
                if normalizedHost == nil {
                    Label("Enter an IPv4 address or hostname, without a URL or port.", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                } else {
                    Text("Press Return or Apply to change target. Changing the target or timing clears history.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Sampling") {
                Stepper("Ping interval: \(config.pingInterval)s", value: $config.pingInterval, in: 1...60)
                Stepper("Reply timeout: \(config.pingTimeout)s", value: $config.pingTimeout, in: 1...60)
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                    .disabled(!loginItem.isBundled)
                if !loginItem.isBundled {
                    Text("Available when running Pingacik.app. Move it to Applications first.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if loginItem.status == .requiresApproval {
                    Button("Allow Pingacik in Login Items…", action: loginItem.openSettings)
                }
                if let error = loginItem.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { draftHost = config.host; loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in loginItem.refresh() }
    }

    private func applyHost() {
        guard let host = normalizedHost else { return }
        if host != config.host { config.host = host }
        draftHost = host
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject var config: Config
    var body: some View {
        Form {
            Section("Display") {
                Toggle("Show latency in menu bar", isOn: $config.showLatencyText)
                Picker("Default chart range", selection: $config.defaultTimescale) {
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("1 hour").tag(3600)
                }
            }
            Section("Status colors") {
                Toggle("Use custom colors", isOn: $config.useCustomColors)
                ColorPicker("OK", selection: $config.okColor, supportsOpacity: false).disabled(!config.useCustomColors)
                ColorPicker("Warning", selection: $config.warningColor, supportsOpacity: false).disabled(!config.useCustomColors)
                ColorPicker("Critical", selection: $config.criticalColor, supportsOpacity: false).disabled(!config.useCustomColors)
                Text("System colors adapt to light and dark mode. Checking, paused, and stale indicators stay neutral.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThresholdsSettingsView: View {
    @ObservedObject var config: Config
    var body: some View {
        Form {
            Section("Consecutive samples") {
                Stepper("Warning after \(config.yellowAfter)", value: $config.yellowAfter, in: 1...(config.redAfter - 1))
                Stepper("Critical after \(config.redAfter)", value: $config.redAfter, in: (config.yellowAfter + 1)...60)
                Stepper("Recover after \(config.recoverAfter) good replies", value: $config.recoverAfter, in: 1...60)
                Text("Applies to consecutive missed replies or slow replies. A good reply is faster than the warning threshold.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Latency") {
                Stepper("Warning above \(config.yellowMs) ms", value: $config.yellowMs, in: 1...(config.redMs - 1), step: 10)
                Stepper("Critical above \(config.redMs) ms", value: $config.redMs, in: (config.yellowMs + 1)...10000, step: 10)
                Text("Critical thresholds must remain above warning thresholds.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
