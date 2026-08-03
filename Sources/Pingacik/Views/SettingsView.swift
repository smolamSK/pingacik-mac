import SwiftUI

/// Configure Pingacik…, mirroring the plasmoid's config dialog: General,
/// Appearance and Thresholds pages.
struct SettingsView: View {
    @ObservedObject var config: Config

    var body: some View {
        TabView {
            GeneralSettingsView(config: config)
                .tabItem { Label("General", systemImage: "gearshape") }
            AppearanceSettingsView(config: config)
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
            ThresholdsSettingsView(config: config)
                .tabItem { Label("Thresholds", systemImage: "slider.horizontal.3") }
        }
        .frame(width: 420, height: 340)
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var config: Config

    var body: some View {
        Form {
            TextField("Host", text: $config.host)
            Stepper("Ping interval: \(config.pingInterval)s", value: $config.pingInterval, in: 1...60)
            Stepper("Reply timeout: \(config.pingTimeout)s", value: $config.pingTimeout, in: 1...60)
            Toggle("Show latency text in menu bar", isOn: $config.showLatencyText)
            Picker("Default chart timescale", selection: $config.defaultTimescale) {
                Text("30s").tag(30)
                Text("1m").tag(60)
                Text("5m").tag(300)
                Text("15m").tag(900)
                Text("1h").tag(3600)
            }
        }
        .padding()
    }
}

private struct AppearanceSettingsView: View {
    @ObservedObject var config: Config

    var body: some View {
        Form {
            Toggle("Use custom colors", isOn: $config.useCustomColors)
            ColorPicker("OK", selection: $config.okColor, supportsOpacity: false)
                .disabled(!config.useCustomColors)
            ColorPicker("Warning", selection: $config.warningColor, supportsOpacity: false)
                .disabled(!config.useCustomColors)
            ColorPicker("Critical", selection: $config.criticalColor, supportsOpacity: false)
                .disabled(!config.useCustomColors)

            Text("Off by default, the indicator follows your system's green/orange/red, including light/dark switches. Turn this on to pin your own colors — used everywhere: the menu bar dot, the popup header, the log rows and the chart's loss bands.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

private struct ThresholdsSettingsView: View {
    @ObservedObject var config: Config

    var body: some View {
        Form {
            Section("Consecutive samples") {
                Stepper("Warning after \(config.yellowAfter)", value: $config.yellowAfter, in: 1...60)
                Stepper("Critical after \(config.redAfter)", value: $config.redAfter, in: 1...60)
                Stepper("Recover after \(config.recoverAfter)", value: $config.recoverAfter, in: 1...60)
            }
            Section("Latency") {
                Stepper("Warning above \(config.yellowMs) ms", value: $config.yellowMs, in: 1...10000, step: 10)
                Stepper("Critical above \(config.redMs) ms", value: $config.redMs, in: 1...10000, step: 10)
            }
        }
        .padding()
    }
}
