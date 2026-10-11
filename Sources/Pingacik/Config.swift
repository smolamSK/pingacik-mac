import Foundation
import SwiftUI
import PingacikCore

/// User-facing settings, persisted to UserDefaults. Keys and defaults mirror
/// the upstream KDE plasmoid's config/main.xml one-for-one, so anyone who
/// knows that widget will recognize these.
@MainActor
final class Config: ObservableObject {
    private enum Keys {
        static let host = "host"
        static let pingInterval = "pingInterval"
        static let pingTimeout = "pingTimeout"
        static let showLatencyText = "showLatencyText"
        static let defaultTimescale = "defaultTimescale"
        static let useCustomColors = "useCustomColors"
        static let okColor = "okColor"
        static let warningColor = "warningColor"
        static let criticalColor = "criticalColor"
        static let yellowAfter = "yellowAfter"
        static let redAfter = "redAfter"
        static let recoverAfter = "recoverAfter"
        static let yellowMs = "yellowMs"
        static let redMs = "redMs"
    }

    private let defaults: UserDefaults

    // General
    @Published var host: String { didSet { defaults.set(host, forKey: Keys.host) } }
    @Published var pingInterval: Int { didSet { defaults.set(pingInterval, forKey: Keys.pingInterval) } }
    @Published var pingTimeout: Int { didSet { defaults.set(pingTimeout, forKey: Keys.pingTimeout) } }
    @Published var showLatencyText: Bool { didSet { defaults.set(showLatencyText, forKey: Keys.showLatencyText) } }
    @Published var defaultTimescale: Int { didSet { defaults.set(defaultTimescale, forKey: Keys.defaultTimescale) } }

    // Appearance
    @Published var useCustomColors: Bool { didSet { defaults.set(useCustomColors, forKey: Keys.useCustomColors) } }
    @Published var okColor: Color { didSet { defaults.set(okColor.hexString, forKey: Keys.okColor) } }
    @Published var warningColor: Color { didSet { defaults.set(warningColor.hexString, forKey: Keys.warningColor) } }
    @Published var criticalColor: Color { didSet { defaults.set(criticalColor.hexString, forKey: Keys.criticalColor) } }

    // Thresholds (key names kept as in main.xml even though labels are OK/Warning/Critical)
    @Published var yellowAfter: Int { didSet { defaults.set(yellowAfter, forKey: Keys.yellowAfter) } }
    @Published var redAfter: Int { didSet { defaults.set(redAfter, forKey: Keys.redAfter) } }
    @Published var recoverAfter: Int { didSet { defaults.set(recoverAfter, forKey: Keys.recoverAfter) } }
    @Published var yellowMs: Int { didSet { defaults.set(yellowMs, forKey: Keys.yellowMs) } }
    @Published var redMs: Int { didSet { defaults.set(redMs, forKey: Keys.redMs) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        host = MonitoringTarget.normalizedHost(Self.loadString(defaults, Keys.host, "8.8.8.8")) ?? "8.8.8.8"
        pingInterval = min(60, max(1, Self.loadInt(defaults, Keys.pingInterval, 1)))
        pingTimeout = min(60, max(1, Self.loadInt(defaults, Keys.pingTimeout, 1)))
        showLatencyText = Self.loadBool(defaults, Keys.showLatencyText, true)
        let savedTimescale = Self.loadInt(defaults, Keys.defaultTimescale, 300)
        defaultTimescale = [30, 60, 300, 900, 3600].contains(savedTimescale) ? savedTimescale : 300

        useCustomColors = Self.loadBool(defaults, Keys.useCustomColors, false)
        okColor = Color(hex: Self.loadString(defaults, Keys.okColor, "#27ae60"))
        warningColor = Color(hex: Self.loadString(defaults, Keys.warningColor, "#f67400"))
        criticalColor = Color(hex: Self.loadString(defaults, Keys.criticalColor, "#da4453"))

        let warningCount = min(59, max(1, Self.loadInt(defaults, Keys.yellowAfter, 2)))
        yellowAfter = warningCount
        redAfter = min(60, max(warningCount + 1, Self.loadInt(defaults, Keys.redAfter, 5)))
        recoverAfter = min(60, max(1, Self.loadInt(defaults, Keys.recoverAfter, 5)))
        let warningLatency = min(9999, max(1, Self.loadInt(defaults, Keys.yellowMs, 150)))
        yellowMs = warningLatency
        redMs = min(10000, max(warningLatency + 1, Self.loadInt(defaults, Keys.redMs, 500)))
    }

    var thresholds: Thresholds {
        Thresholds(
            yellowAfter: yellowAfter,
            redAfter: redAfter,
            recoverAfter: recoverAfter,
            yellowMs: Double(yellowMs),
            redMs: Double(redMs)
        )
    }

    private static func loadInt(_ defaults: UserDefaults, _ key: String, _ fallback: Int) -> Int {
        defaults.object(forKey: key) != nil ? defaults.integer(forKey: key) : fallback
    }

    private static func loadBool(_ defaults: UserDefaults, _ key: String, _ fallback: Bool) -> Bool {
        defaults.object(forKey: key) != nil ? defaults.bool(forKey: key) : fallback
    }

    private static func loadString(_ defaults: UserDefaults, _ key: String, _ fallback: String) -> String {
        defaults.string(forKey: key) ?? fallback
    }
}

extension Config {
    /// The color used for `status` everywhere — the menu bar dot, the popup
    /// header, the log rows and the chart bands — so they always agree.
    /// Follows the system semantic colors (and so light/dark switches)
    /// unless the user opted into custom colors.
    func color(for status: ConnectionStatus) -> Color {
        switch status {
        case .ok: return useCustomColors ? okColor : Color(nsColor: .systemGreen)
        case .warning: return useCustomColors ? warningColor : Color(nsColor: .systemOrange)
        case .critical: return useCustomColors ? criticalColor : Color(nsColor: .systemRed)
        }
    }
}
