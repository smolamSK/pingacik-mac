# Pingacik for macOS

A menu bar app that monitors internet connection quality by pinging a host. It's a native macOS
port of [smolamSK/pingacik](https://github.com/smolamSK/pingacik), a KDE Plasma 6 panel widget,
rebuilt with SwiftUI + AppKit for the Mac menu bar.

The menu bar shows a status indicator and the current round-trip time in a stable-width label.
Click it for a latency summary, an RTT chart, and a live probe log. Checking, paused, and stale
measurements use neutral indicators; warning and critical states include a symbol as well as color.

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

To run it every time you log in, move `Pingacik.app` into `/Applications`, then enable
**Launch at login** in General settings. If macOS requires approval, use the link shown there
to open Login Items. This control is unavailable when running the unbundled executable.
Registration uses [Apple’s SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice);
the app reads its actual registration status and displays registration errors.

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

**It degrades when a consecutive-sample threshold is reached and recovers slowly.** Both missed
replies and slow replies must meet the configured consecutive-sample count. Returning to OK
requires `recoverAfter` consecutive good pings. A "good" ping got a
reply *and* came back faster than the Warning latency threshold.

| Trigger | Default |
|---|---|
| Warning after N consecutive lost pings | 2 |
| Critical after N consecutive lost pings | 5 |
| Warning above | 150 ms |
| Critical above | 500 ms |
| Back to OK after N consecutive good pings | 5 |

Packet loss and latency are evaluated separately and the worse of the two wins, so a link that
delivers every packet but takes 800 ms still reads Critical once the sample threshold is met.
With the default thresholds, one lost or slow ping does not change the underlying connection
state. Losses must be *consecutive*, and any reply resets the loss count.

## Settings

Click the menu bar item → **Settings…**.

**General** — target IPv4 address or hostname (default `8.8.8.8`), ping interval, reply timeout,
and launch at login. Host edits stay in a draft until Return or **Apply**; invalid hosts, URLs,
and ports are rejected inline. IPv6 targets are not currently supported.

**Appearance** — whether to show the latency text in the menu bar, the chart range the popup opens
with, and the three state colors.

By default the colors follow the system's green/orange/red, so they adapt to light/dark mode
automatically. Turn on **Use custom colors** to pin your own for OK, Warning and Critical — used
everywhere: the menu bar dot, the popup header, the log rows and the chart's loss bands.

**Thresholds** — everything in the table above. Critical values must remain above warning values.
Invalid saved timing and threshold values are normalized when settings load.

Changing the host, interval or timeout clears collected history and returns the indicator to
**Checking** until a fresh result arrives. Results from an old target or sampling session are ignored.

## Monitoring and diagnostics

- **Pause / Resume** in the popup stops or restarts sampling while preserving history. Resume waits
  for a fresh result before displaying a live status. Sleep suspends sampling; wake starts a fresh
  session unless monitoring was manually paused. Unexpected gaps show **No recent data**.
- Recovery displays progress, for example **3 of 5 good replies to recover**. A missed reply is
  visible immediately, even before the overall warning threshold is reached.
- Failures distinguish no reply, host lookup failure, unreachable hosts, launch errors, and a
  stalled ping process. Diagnostic output is available in the popup and log tooltips.
- The **…** menu provides **Copy diagnostics**, **Export diagnostics…**, and **Quit Pingacik**.
  Reports include the target, timing, status, and retained samples with timestamps and failure
  details. Reports are written or copied only when requested.
- The summary uses the selected chart range; the latest RTT and latest 50 log entries remain live.
  Loss counts probes without a reply, including target and process errors, rather than claiming
  to isolate network packet loss. A single ICMP target measures that target’s reachability, not
  every aspect of internet connectivity.

## Notes

- History is kept in memory — roughly the last hour at the default 1 s interval. It resets
  when the app restarts. Settings are saved automatically; diagnostic reports are saved only
  when you choose Export.
- The chart downsamples uninterrupted runs toward ~300 points while preserving breaks for failed
  probes, pauses, and sleep. Failed probes are shaded over their actual start/end times.
- **Auto** scale follows measured latency. **Thresholds** scale includes both threshold lines;
  upward arrows identify thresholds above the visible auto scale. The x-axis always covers the
  selected range, even while the history is still filling.
- Only one ping is ever in flight. The next one is scheduled from when the last one *started*, so a
  reply that took 300 ms is followed 700 ms later — the cadence holds at the configured interval
  instead of drifting, and a stalled link can't pile up processes.
- The menu bar item can't use SwiftUI's `MenuBarExtra` — it renders its label as a monochrome
  template image no matter what you draw, which silently strips the traffic-light color. This app
  hosts a plain `NSHostingView` inside a raw `NSStatusItem` instead, which sidesteps that and
  renders color normally.

## Development

```sh
swift test    # core logic, monitor regressions, settings validation, and a local loopback ping
swift run     # launch the app
```

`PingacikCoreTests` includes upstream's state-machine cases plus validation, failure parsing,
chart continuity/scaling, and diagnostic reporting. `PingacikTests` covers settings propagation,
late callbacks, pause/resume, sleep/wake, recovery, and the real ping runner against `127.0.0.1`.

### Layout

```
Package.swift
Sources/
  PingacikCore/            pure logic, no AppKit/SwiftUI — unit tested in isolation
    PingSample.swift          sample type + failure-aware ping-output parsing
    MonitoringTarget.swift    sampling configuration + host validation
    ChartData.swift           chart runs, outage boundaries, adaptive scale
    Diagnostics.swift         text diagnostic reports
    PingState.swift           classify, hysteresis state machine, scheduling, ring buffer,
                               downsampling, stats
  Pingacik/                 the app
    PingacikApp.swift         @main + AppDelegate: NSStatusItem, NSPopover, settings window
    PingRunner.swift          single-flight ping executor + scheduling + watchdog
    Config.swift               settings, persisted to UserDefaults
    ColorHex.swift             Color <-> hex string, for persisting custom colors
    Model/
      PingMonitor.swift        session lifecycle + state machine + live state
      LoginItem.swift          launch-at-login registration and errors
    Views/
      MenuBarLabel.swift        the menu bar dot + latency text
      PopoverView.swift         header stats, timescale picker, chart, log
      RTTChartView.swift        Swift Charts RTT line + loss bands
      SettingsView.swift        General / Appearance / Thresholds tabs
Tests/
  PingacikCoreTests/         pure logic and chart tests
  PingacikTests/             monitor regressions and process integration
Resources/
  AppIcon.icns               app icon (see Scripts/build-app.sh)
  Info.plist                 bundle metadata: LSUIElement, icon file, bundle id
Scripts/
  build-app.sh                builds a release binary and assembles dist/Pingacik.app
```

## Credit

Ported from [smolamSK/pingacik](https://github.com/smolamSK/pingacik) (GPL-3.0-or-later), which
this follows closely in behavior and defaults.
