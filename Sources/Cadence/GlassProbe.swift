import AppKit
import SwiftUI

/// `Cadence --glass-probe <dir>` puts each glass recipe in a real transparent
/// panel and dumps what the app draws in-process via `cacheDisplay`.
///
/// This needs no Screen Recording permission. It cannot show WindowServer
/// compositing — a `.behindWindow` blur is composited outside the process and
/// will read as empty here — which is exactly what makes it useful: it tells us
/// whether `glassEffect` paints anything itself, and therefore whether the
/// `Backdrop` underneath it is doing the work or fighting it.
@MainActor
enum GlassProbe {

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--glass-probe") else { return false }
        let dir = args.count > flag + 1 ? args[flag + 1] : FileManager.default.currentDirectoryPath
        run(into: URL(fileURLWithPath: dir))
        return true
    }

    private static func run(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        capture("regular-only", into: dir) {
            Text("Regular")
                .padding(.horizontal, 20).frame(height: 44)
                .glassEffect(.regular, in: .capsule)
        }

        capture("clear-only", into: dir) {
            Text("Clear")
                .padding(.horizontal, 20).frame(height: 44)
                .glassEffect(.clear, in: .capsule)
        }

        capture("backdrop-only", into: dir) {
            Text("Backdrop")
                .padding(.horizontal, 20).frame(height: 44)
                .background(Backdrop().clipShape(Capsule()))
        }

        capture("backdrop-plus-clear", into: dir) {
            Text("Both")
                .padding(.horizontal, 20).frame(height: 44)
                .background(Backdrop().clipShape(Capsule()))
                .glassEffect(.clear, in: .capsule)
        }

        capture("tinted-regular", into: dir) {
            Text("Tinted")
                .padding(.horizontal, 20).frame(height: 44)
                .glassEffect(.regular.tint(.blue), in: .capsule)
        }
    }

    private static func capture<V: View>(_ name: String, into dir: URL, @ViewBuilder content: () -> V) {
        let panel = NSPanel(
            contentRect: NSRect(x: 200, y: 200, width: 240, height: 90),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating

        let hosting = NSHostingView(rootView: ZStack { content() }.frame(width: 240, height: 90))
        panel.contentView = hosting
        panel.orderFrontRegardless()
        panel.displayIfNeeded()

        // Let SwiftUI settle before reading pixels back.
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))

        guard let view = panel.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else {
            print("\(name): could not make a bitmap")
            panel.orderOut(nil)
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)

        var opaquePixels = 0
        var sampled = 0
        for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
                sampled += 1
                if let colour = rep.colorAt(x: x, y: y), colour.alphaComponent > 0.02 {
                    opaquePixels += 1
                }
            }
        }
        let coverage = sampled > 0 ? Double(opaquePixels) / Double(sampled) : 0
        print(String(format: "%-22@ draws %.0f%% of its own pixels in-process", name as NSString, coverage * 100))

        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
        }
        panel.orderOut(nil)
    }
}

/// `Cadence --capture <dir>` renders each window's content in-process.
///
/// Liquid Glass and behind-window blur are composited outside the process and
/// will be missing, but layout, type, spacing, colour and every AppKit control
/// draw here — which is most of what a design review is about.
@MainActor
enum WindowCapture {

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--capture") else { return false }
        let dir = args.count > flag + 1 ? args[flag + 1] : FileManager.default.currentDirectoryPath
        run(into: URL(fileURLWithPath: dir))
        return true
    }

    private static func run(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = Store()
        let scheduler = Scheduler(store: store)

        shoot("settings", size: CGSize(width: 900, height: 660), into: dir) {
            AnyView(SettingsView().environmentObject(store).environmentObject(scheduler))
        }

        if let water = store.config.reminders.first(where: { $0.category == .hydration }) {
            shoot("settings-reminder", size: CGSize(width: 900, height: 900), into: dir) {
                AnyView(SettingsView(previewReminder: water.id)
                    .environmentObject(store).environmentObject(scheduler))
            }
        }

        let bar = CommandBarController(store: store, scheduler: scheduler)
        shoot("command-bar", size: CGSize(width: 660, height: 420), into: dir) {
            AnyView(CommandBarView(controller: bar)
                .environmentObject(store).environmentObject(scheduler))
        }

        let session = AlertPresenter.BreakSession(reminder: PresetLibrary.eyeBreak, seconds: 20)
        session.remaining = 13
        session.canDismiss = true
        session.companions = store.config.reminders.filter { !$0.alert.isBlocking }.prefix(2).map { $0 }
        shoot("overlay", size: CGSize(width: 1280, height: 800), into: dir) {
            AnyView(BreakOverlayView(session: session, onDone: {}, onSkip: {}, onCompanion: { _ in }))
        }

        if let water = store.config.reminders.first(where: { $0.category == .hydration }) {
            shoot("pill", size: CGSize(width: 720, height: 120), into: dir) {
                AnyView(
                    VStack {
                        PillView(
                            reminder: water,
                            progress: "1,500 / 3,000 ml",
                            onDone: {}, onSnooze: {}, onSkip: {}
                        )
                        Spacer()
                    }
                )
            }
        }
    }

    private static func shoot(
        _ name: String,
        size: CGSize,
        into dir: URL,
        content: () -> AnyView
    ) {
        let window = NSWindow(
            contentRect: NSRect(origin: .init(x: 100, y: 100), size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = NSHostingView(
            rootView: ZStack {
                // Stand-in for the desktop, so translucent surfaces are legible.
                LinearGradient(
                    colors: [Color(hex: 0x2B3550), Color(hex: 0x121722)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                content()
            }
            .frame(width: size.width, height: size.height)
        )
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
            print("captured \(name)")
        }
        window.orderOut(nil)
    }
}
