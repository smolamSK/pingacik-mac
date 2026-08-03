# Pingacik for macOS

A menu bar app that monitors internet connection quality by pinging a host. It's a native macOS
port of [smolamSK/pingacik](https://github.com/smolamSK/pingacik), a KDE Plasma 6 panel widget,
rebuilt with SwiftUI + AppKit for the Mac menu bar.

The menu bar shows a traffic-light dot and the current round-trip time. Click it for a live ping
log and an RTT chart over a configurable timescale.

## Install / run

Requires Xcode (for the Swift toolchain) and macOS 14+.

Build it as a proper `.app` (recommended):

```sh
git clone <this repo>
cd pingacik-mac
./Scripts/build-app.sh
open dist/Pingacik.app
```

This builds a release binary, assembles `dist/Pingacik.app` with its icon and `Info.plist`, and
ad-hoc code signs it. Drag it into `/Applications` if you want it there. `LSUIElement` in the
Info.plist keeps it out of the Dock and Cmd-Tab, so once it's running you'll only see it in the
menu bar.

To run it every time you log in, add `Pingacik.app` as a login item in System Settings → General →
Login Items.

Alternatively, run it straight from the Swift package without bundling (useful while developing —
`swift run` picks up code changes without re-running the build script):

```sh
swift build -c release
.build/release/Pingacik
```

This unbundled form still hides its Dock icon (it sets itself as an accessory app in code), but has
no custom app icon since there's no `Info.plist`/bundle for macOS to read one from.

## How the states work

The app sends one `ping -c 1` per interval and feeds each result into a hysteresis state machine.

The three states are **OK**, **Warning** and **Critical**.

**It degrades immediately but recovers slowly.** Crossing a threshold changes the state on the very
next sample; returning to OK requires `recoverAfter` consecutive good pings. A "good" ping got a
reply *and* came back faster than the Warning latency threshold.

| Trigger | Default |
|---|---|
| Warning after N consecutive lost pings | 2 |
| Critical after N consecutive lost pings | 5 |
| Warning above | 150 ms |
| Critical above | 500 ms |
| Back to OK after N consecutive good pings | 5 |

Packet loss and latency are evaluated separately and the worse of the two wins, so a link that
delivers every packet but takes 800 ms still reads Critical. A single lost or slow ping never
changes the state — losses must be *consecutive*, and any reply resets the loss count.

## Settings

Click the menu bar item → **Settings…**.

**General** — target host (default `8.8.8.8`), ping interval and reply timeout.

**Appearance** — whether to show the latency text in the menu bar, the chart range the popup opens
with, and the three state colors.

By default the colors follow the system's green/orange/red, so they adapt to light/dark mode
automatically. Turn on **Use custom colors** to pin your own for OK, Warning and Critical — used
everywhere: the menu bar dot, the popup header, the log rows and the chart's loss bands.

**Thresholds** — everything in the table above.

Changing the host, interval or timeout clears the collected history and resets the status to OK,
since it's no longer comparable to samples against the old target.

## Notes

- History is kept in memory only — roughly the last hour at the default 1 s interval. It resets
  when the app restarts. Nothing is written to disk except your settings (in `UserDefaults`).
- The chart downsamples to ~300 buckets, so the 1 h view stays responsive. Buckets containing lost
  packets are shaded in the critical color, proportional to how many were lost.
- Only one ping is ever in flight. The next one is scheduled from when the last one *started*, so a
  reply that took 300 ms is followed 700 ms later — the cadence holds at the configured interval
  instead of drifting, and a stalled link can't pile up processes.
- The menu bar item can't use SwiftUI's `MenuBarExtra` — it renders its label as a monochrome
  template image no matter what you draw, which silently strips the traffic-light color. This app
  hosts a plain `NSHostingView` inside a raw `NSStatusItem` instead, which sidesteps that and
  renders color normally.

## Development

```sh
swift test    # PingacikCoreTests — parsing, hysteresis, cadence, ring buffer, downsampling, stats
swift run     # launch the app
```

`PingacikCoreTests` ports the same cases as upstream's `tools/test-pingstate.js`.

### Layout

```
Package.swift
Sources/
  PingacikCore/            pure logic, no AppKit/SwiftUI — unit tested in isolation
    PingSample.swift          sample type + ping-output parsing
    PingState.swift           classify, hysteresis state machine, scheduling, ring buffer,
                               downsampling, stats
  Pingacik/                 the app
    PingacikApp.swift         @main + AppDelegate: NSStatusItem, NSPopover, settings window
    PingRunner.swift          single-flight ping executor + scheduling + watchdog
    Config.swift               settings, persisted to UserDefaults
    ColorHex.swift             Color <-> hex string, for persisting custom colors
    Model/
      PingMonitor.swift        wires Config + PingRunner + the state machine, publishes live state
    Views/
      MenuBarLabel.swift        the menu bar dot + latency text
      PopoverView.swift         header stats, timescale picker, chart, log
      RTTChartView.swift        Swift Charts RTT line + loss bands
      StatusDot.swift           shared status circle
      SettingsView.swift        General / Appearance / Thresholds tabs
Tests/
  PingacikCoreTests/         XCTest port of upstream's test-pingstate.js
Resources/
  AppIcon.icns               app icon (see Scripts/build-app.sh)
  Info.plist                 bundle metadata: LSUIElement, icon file, bundle id
Scripts/
  build-app.sh                builds a release binary and assembles dist/Pingacik.app
```

## Credit

Ported from [smolamSK/pingacik](https://github.com/smolamSK/pingacik) (GPL-3.0-or-later), which
this follows closely in behavior and defaults.
