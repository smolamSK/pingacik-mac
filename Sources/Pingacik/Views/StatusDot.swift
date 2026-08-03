import SwiftUI
import PingacikCore

/// Shared status circle used by the menu bar label and the popup header.
struct StatusDot: View {
    let status: ConnectionStatus
    @ObservedObject var config: Config
    var diameter: CGFloat = 8

    var body: some View {
        Circle()
            .fill(config.color(for: status))
            .frame(width: diameter, height: diameter)
    }
}
