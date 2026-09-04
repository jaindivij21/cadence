# Cadence

A quiet reminder app that lives in the macOS menu bar.

Reminders apps are built around lists you have to open. Cadence is built around
the opposite idea: you should not have to look at it. A glass island floats
above your desktop counting down to the next thing, and interrupts you exactly
as hard as that thing deserves — it morphs in place to ask about a glass of
water, and takes over every screen for a break your eyes actually need.

Native Swift and SwiftUI, built on macOS 26's Liquid Glass. No Electron, no
dependencies, no account, no network. Everything is a JSON file in
`~/Library/Application Support/Cadence`.

## The island

A borderless glass panel, draggable anywhere, that stays out of the way:

- **Idle** — a capsule with the next reminder's icon, a ring showing how far
  through the interval you are, and the countdown.
- **Hover** — it expands. The name appears, an action button appears, and a
  squircle opens everything else.
- **Due** — the same capsule morphs in place into the question, with the answer
  buttons inline. No second window slides in from the corner.
- **Counters** — one ringed circle per countable habit, showing how many are
  left today. Click one to log it.

Built with `GlassEffectContainer` and `glassEffectID`, so the shapes merge and
separate as one liquid object rather than as separate views appearing.

Turn it off in Settings and everything falls back to a corner card; the menu bar
item works either way.

## What it does

**Three ways to schedule something**

| Schedule | Behaviour | Good for |
| --- | --- | --- |
| Every N minutes | Counts from the last time you answered it | 20-20-20 breaks, posture, standing up |
| N times a day | Spread evenly across your waking window | Medication, water, anything with a dose count |
| At set times | Fires at the clock times you pick | Supplements, daylight, a wind-down |

**Two ways to be interrupted**

- **Ask in the island.** Never steals focus. Answer it, snooze it, or let it
  fade. Set it to wait until you answer if it matters.
- **The whole screen.** Your desktop, frosted, with one instruction and a
  countdown floating on it. It clears itself when the timer runs out. Use it for
  anything you physically cannot do while looking at a display.

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

- **Screen & eyes** — 20-20-20, distance focus, cold and warm compress
- **Medication** — morning and evening doses, or 2× / 3× / 4× / 6× a day
- **Hydration** — water, electrolytes
- **Immunity & recovery** — cold exposure, daylight, supplements, breathwork, screens down
- **Movement** — stand and move, posture reset, mobility
- **Focus** — shutdown ritual

A preset is a normal reminder the moment you add it. Rename it, re-time it,
change how loudly it interrupts, delete it.

Nothing in the library names a condition or a prescription. "Medication · 4× a
day" is as specific as it gets; what you are actually taking, and what you need
to remember about taking it, belongs in your copy of the reminder. The app ships
knowing nothing about you.

## Install

Requires macOS 26 (Tahoe) or later and the Xcode command line tools. Cadence is
built on Liquid Glass, which does not exist before Tahoe, and there is no
fallback that still looks like this.

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
swift build                          # debug build
swift run Cadence                    # run without bundling
.build/release/Cadence --smoke-test  # window construction, alert queue, schedule maths
```

There is no screenshot mode. Every surface is real system material — Liquid
Glass, `NavigationSplitView`, `Form` — and none of it renders through
`ImageRenderer`. The only way to review the look is to run the app.

### Layout

```
Sources/Cadence/
  CadenceApp.swift        @main, the menu bar scene, wiring
  Models.swift            Reminder, Schedule, AlertStyle, the preset library
  Store.swift             JSON persistence and the daily log
  Scheduler.swift         When things fire, idle detection, missed-slot handling
  AlertPresenter.swift    Routes a due reminder to the island or the whole screen
  IslandController.swift  The floating panel: placement, resizing, dragging
  Theme.swift             Palette, type scale, the glass shape vocabulary
  SmokeTest.swift         --smoke-test
  Views/                  Island, overlay, corner card, panel, settings
Tools/makeicon.swift    Draws the app icon, so no binary artwork is committed
```

## Licence

MIT.
