# Cadence

A quiet reminder app that lives in the macOS menu bar.

Reminders apps are built around lists you have to open. Cadence is built around
the opposite idea: you should not have to look at it. It sits in the menu bar,
counts down to the next thing, and interrupts you exactly as hard as that thing
deserves — a card in the corner for a glass of water, the whole screen for a
break your eyes actually need.

Native Swift and SwiftUI. No Electron, no dependencies, no account, no network.
Everything is a JSON file in `~/Library/Application Support/Cadence`.

## What it does

**Three ways to schedule something**

| Schedule | Behaviour | Good for |
| --- | --- | --- |
| Every N minutes | Counts from the last time you answered it | 20-20-20 breaks, posture, standing up |
| N times a day | Spread evenly across your waking window | Medication, water, anything with a dose count |
| At set times | Fires at the clock times you pick | Supplements, daylight, a wind-down |

**Two ways to be interrupted**

- **A card in the corner.** Never steals focus. Answer it, snooze it, or let it
  fade. Set it to wait until you answer if it matters.
- **The whole screen.** A dark, blurred take-over with one instruction and a
  countdown. It clears itself when the timer runs out. Use it for anything you
  physically cannot do while looking at a display.

**Counting**

Give a reminder an amount, a unit and a daily target and Cadence tracks the
running total: twelve 250 ml prompts add up to a 3 litre day, with a progress
bar and an undo button in the panel.

**It knows when you are not there**

If you have been away from the keyboard for a few minutes, repeating timers
reset — you already had the break. A scheduled dose that goes unanswered past
its grace period is written down as missed rather than ambushing you three hours
late. Any full-screen break also restarts the 20-20-20 clock, because it counts.

## What it ships with

A new install starts with six habits that suit anyone who sits in front of a
screen: a 20-20-20 break, 3 litres of water, stand and move, daylight,
supplements, and a screens-down cue at night.

Everything else comes from the preset library in **Settings → Add**:

- **Screen & eyes** — 20-20-20, distance focus, warm compress
- **Medication** — drops at 6× / 4× / 2× a day, morning and evening doses
- **Hydration** — water, electrolytes
- **Immunity & recovery** — cold exposure, daylight, supplements, breathwork, screens down
- **Movement** — stand and move, posture reset, mobility
- **Focus** — shutdown ritual

A preset is a normal reminder the moment you add it. Rename it, re-time it,
change how loudly it interrupts, delete it.

## Install

Requires macOS 14 or later and the Xcode command line tools.

```sh
git clone https://github.com/jaindivij21/cadence.git
cd cadence
./build.sh
open -a Cadence
```

`build.sh` compiles a release binary, draws the icon, assembles `Cadence.app`,
signs it ad hoc and moves it to `/Applications`. Pass `--no-install` to leave
the bundle in the working directory instead.

Turn on **Start Cadence at login** in Settings and you never think about it again.

## Your data

One file: `~/Library/Application Support/Cadence/state.json`. It holds your
configuration and 30 days of history — what you did, what you skipped, what you
missed. Nothing is sent anywhere. There is no analytics, no account, no network
code in this app at all. Delete the file to start over.

## Development

```sh
swift build                      # debug build
swift run Cadence                # run without bundling

.build/release/Cadence --smoke-test              # check window and schedule maths
.build/release/Cadence --render-previews ./out   # PNG of every screen
```

`--render-previews` exists because the panel and the overlay are hard to review
by hand. It writes the panel, both settings panes, the break overlay and the
corner card straight to disk. AppKit-backed controls (switches, steppers, date
pickers, blur) render as yellow placeholders — `ImageRenderer` cannot draw them,
and that is expected.

### Layout

```
Sources/Cadence/
  CadenceApp.swift      @main, the menu bar scene, wiring
  Models.swift          Reminder, Schedule, AlertStyle, the preset library
  Store.swift           JSON persistence and the daily log
  Scheduler.swift       When things fire, idle detection, missed-slot handling
  AlertPresenter.swift  Every window that is not the panel
  Theme.swift           Palette, type scale, shared chrome
  Views/                Panel, overlay, corner card, settings
Tools/makeicon.swift    Draws the app icon, so no binary artwork is committed
```

## Licence

MIT.
