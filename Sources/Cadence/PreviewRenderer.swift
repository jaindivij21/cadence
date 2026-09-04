import AppKit
import SwiftUI

/// Development helper. `Cadence --render-previews <dir>` writes a PNG of each
/// surface and exits, so the design can be reviewed without launching the app
/// and clicking through it.
@MainActor
enum PreviewRenderer {

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        if args.contains("--smoke-test") {
            smokeTest()
            return true
        }
        guard let flag = args.firstIndex(of: "--render-previews") else { return false }
        let dir = args.count > flag + 1 ? args[flag + 1] : FileManager.default.currentDirectoryPath
        render(into: URL(fileURLWithPath: dir))
        return true
    }

    /// Exercises the window code paths that previews cannot reach: the
    /// full-screen overlay and the corner card actually being built and placed.
    private static func smokeTest() {
        var failures: [String] = []
        let presenter = AlertPresenter()
        var answered: [(String, EventKind)] = []
        presenter.onAnswer = { reminder, kind in answered.append((reminder.name, kind)) }

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

        // A second alert must queue rather than stack on top.
        presenter.present(PresetLibrary.water)
        if presenter.activeToast != nil {
            failures.append("toast appeared while a break was on screen")
        }

        let scheduleChecks = Reminder(
            name: "check", detail: "", symbol: "bell.fill", category: .eye,
            schedule: .timesPerDay(4), alert: .toast(sticky: true)
        )
        let slots = scheduleChecks.slots(global: .defaultWaking)
        if slots.count != 4 { failures.append("timesPerDay(4) produced \(slots.count) slots") }
        if let first = slots.first, let last = slots.last {
            if first < TimeWindow.defaultWaking.start || last > TimeWindow.defaultWaking.end {
                failures.append("slots fall outside the waking window: \(slots)")
            }
            if slots != slots.sorted() { failures.append("slots are not in order: \(slots)") }
        }

        for reminder in Reminder.defaultSet + PresetLibrary.groups.flatMap(\.reminders) {
            if NSImage(systemSymbolName: reminder.symbol, accessibilityDescription: nil) == nil {
                failures.append("\(reminder.name) uses an unknown symbol: \(reminder.symbol)")
            }
        }

        if failures.isEmpty {
            print("smoke test: ok (\(overlays.count) overlay window(s), slots \(slots))")
        } else {
            failures.forEach { print("smoke test FAILED: \($0)") }
        }
    }

    private static func render(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let store = Store()
        let scheduler = Scheduler(store: store)

        write(
            PanelView()
                .environmentObject(store)
                .environmentObject(scheduler),
            named: "panel",
            in: dir
        )

        write(
            SettingsView()
                .environmentObject(store)
                .frame(width: 860, height: 700),
            named: "settings-general",
            in: dir
        )

        if let water = store.config.reminders.first(where: { $0.category == .hydration }) {
            write(
                SettingsView(previewReminder: water.id)
                    .environmentObject(store)
                    .frame(width: 860, height: 1180),
                named: "settings-reminder",
                in: dir
            )
        }

        let session = AlertPresenter.BreakSession(reminder: PresetLibrary.eyeBreak, seconds: 20)
        session.remaining = 13
        session.canDismiss = true
        write(
            BreakOverlayView(session: session, onDone: {}, onSkip: {})
                .frame(width: 1280, height: 800),
            named: "overlay",
            in: dir
        )

        write(
            ToastView(
                reminder: PresetLibrary.water,
                progressText: "1500/3000 ml",
                onDone: {}, onSkip: {}, onSnooze: {}
            )
            .frame(width: 380, height: 150),
            named: "toast",
            in: dir
        )

        print("Rendered previews into \(dir.path)")
    }

    private static func write<V: View>(_ view: V, named name: String, in dir: URL) {
        let renderer = ImageRenderer(
            content: view
                .environment(\.staticRender, true)
                .preferredColorScheme(.dark)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            print("Could not render \(name)")
            return
        }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
