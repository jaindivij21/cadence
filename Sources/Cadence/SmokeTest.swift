import AppKit
import SwiftUI

/// `Cadence --smoke-test` exercises the parts that are easy to break and hard
/// to see: window construction, the alert queue, and the schedule maths.
///
/// There is deliberately no screenshot mode. Every surface is now real system
/// material — Liquid Glass, `NavigationSplitView`, `Form` — and none of it
/// renders through `ImageRenderer`. The only way to review the look is to run
/// the app.
@MainActor
enum SmokeTest {

    static func runIfRequested() -> Bool {
        guard CommandLine.arguments.contains("--smoke-test") else { return false }
        run()
        return true
    }

    private static func run() {
        var failures: [String] = []

        let presenter = AlertPresenter()
        var answered: [(String, EventKind)] = []
        presenter.onAnswer = { reminder, kind in answered.append((reminder.name, kind)) }

        var breakStates: [Bool] = []
        presenter.onBreakChange = { breakStates.append($0) }

        // A blocking alert must cover every screen, above everything else.
        presenter.present(PresetLibrary.eyeBreak)
        let overlays = NSApp.windows.filter { $0 is KeyableWindow }
        if overlays.count != NSScreen.screens.count {
            failures.append("expected \(NSScreen.screens.count) overlay window(s), got \(overlays.count)")
        }
        if overlays.first?.level != .screenSaver {
            failures.append("overlay is not at screen-saver level")
        }
        if presenter.activeBreak == nil {
            failures.append("no active break session")
        }
        if breakStates != [true] {
            failures.append("the island was not told to step aside: \(breakStates)")
        }

        // A second alert queues behind it rather than stacking on top.
        presenter.present(PresetLibrary.water)
        if presenter.activeQuiet != nil {
            failures.append("a quiet alert appeared while a break was on screen")
        }

        // Slot maths: evenly spread, in order, inside the window.
        let sample = Reminder(
            name: "check", detail: "", symbol: "bell.fill", category: .eye,
            schedule: .timesPerDay(4), alert: .toast(sticky: true)
        )
        let slots = sample.slots(global: .defaultWaking)
        if slots.count != 4 {
            failures.append("timesPerDay(4) produced \(slots.count) slots")
        }
        if slots != slots.sorted() {
            failures.append("slots are not in order: \(slots)")
        }
        if let first = slots.first, let last = slots.last,
           first < TimeWindow.defaultWaking.start || last > TimeWindow.defaultWaking.end {
            failures.append("slots fall outside the waking window: \(slots)")
        }

        // Every symbol the app can ship must actually exist.
        for reminder in Reminder.defaultSet + PresetLibrary.groups.flatMap(\.reminders) {
            if NSImage(systemSymbolName: reminder.symbol, accessibilityDescription: nil) == nil {
                failures.append("\(reminder.name) uses an unknown symbol: \(reminder.symbol)")
            }
        }

        // Round-tripping config must not lose anything.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let data = try encoder.encode(Config())
            let restored = try decoder.decode(Config.self, from: data)
            if restored.reminders.count != Config().reminders.count {
                failures.append("config round-trip lost reminders")
            }
        } catch {
            failures.append("config does not round-trip: \(error)")
        }

        if failures.isEmpty {
            print("smoke test: ok — \(overlays.count) overlay window(s), slots \(slots)")
        } else {
            failures.forEach { print("smoke test FAILED: \($0)") }
        }
    }
}
