import SwiftUI
import AppKit
import Combine

/// Owns the status item, popover and settings window directly via AppKit.
///
/// SwiftUI's `MenuBarExtra` renders its label as a monochrome template image
/// no matter the style — Shapes don't draw at all and SF Symbols get
/// flattened to the system foreground color, so the traffic-light dot (the
/// whole point of this app) can't show color through it. Hosting a plain
/// `NSHostingView` as a subview of an `NSStatusItem` button sidesteps that
/// template-image pipeline entirely and renders normally, colors included.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let config = Config()
    private(set) lazy var monitor = PingMonitor(config: config)

    private var statusItem: NSStatusItem?
    private var labelHostingView: NSHostingView<MenuBarLabel>?
    private var popover: NSPopover?
    private var settingsWindowController: NSWindowController?
    private var monitorSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setUpStatusItem()
        setUpPopover()

        monitorSubscription = monitor.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.layoutStatusItem() }
        }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else {
            statusItem = item
            return
        }

        let hosting = NSHostingView(rootView: MenuBarLabel(monitor: monitor, config: config))
        hosting.translatesAutoresizingMaskIntoConstraints = true
        button.addSubview(hosting)

        button.action = #selector(togglePopover(_:))
        button.target = self

        statusItem = item
        labelHostingView = hosting
        layoutStatusItem()
    }

    /// Resizes the status item to fit the label's current content — the
    /// latency text's width changes as the RTT does, same as the plasmoid's
    /// panel dot growing/shrinking with its text.
    private func layoutStatusItem() {
        guard let button = statusItem?.button, let hosting = labelHostingView else { return }
        let size = hosting.fittingSize
        hosting.frame = NSRect(x: 0, y: (button.bounds.height - size.height) / 2, width: size.width, height: size.height)
        statusItem?.length = max(size.width, 22)
    }

    private func setUpPopover() {
        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(
            rootView: PopoverView(monitor: monitor, config: config, openSettings: { [weak self] in self?.openSettings() })
        )
        popover = pop
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button, let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// Opens the settings window directly rather than through SwiftUI's
    /// `Settings` scene / `SettingsLink` — those route through an internal
    /// `showSettingsWindow:` action on the responder chain that never fires
    /// reliably for an accessory app with no window yet on screen.
    private func openSettings() {
        popover?.performClose(nil)

        if settingsWindowController == nil {
            let hosting = NSHostingController(rootView: SettingsView(config: config))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Pingacik Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }

        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }
}

@main
struct PingacikApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(config: appDelegate.config)
        }
    }
}
