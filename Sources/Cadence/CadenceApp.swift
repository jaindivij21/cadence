import AppKit
import Combine
import SwiftUI

/// Owns the long-lived objects and wires them together. Nothing else in the app
/// knows about more than one of them at a time.
@MainActor
final class AppModel: ObservableObject {
    let store: Store
    let scheduler: Scheduler
    let presenter: AlertPresenter
    let commandBar: CommandBarController

    /// Set by the app scene so the island and the panel can open Settings.
    var openSettings: () -> Void = {}

    private var cancellables: Set<AnyCancellable> = []

    init() {
        let store = Store()
        let scheduler = Scheduler(store: store)
        let presenter = AlertPresenter()
        let commandBar = CommandBarController(store: store, scheduler: scheduler)
        self.store = store
        self.scheduler = scheduler
        self.presenter = presenter
        self.commandBar = commandBar

        scheduler.onDue = { [weak store, weak presenter] reminder in
            guard let store, let presenter else { return }
            presenter.soundEnabled = store.config.soundEnabled
            presenter.present(reminder)
        }

        presenter.onAnswer = { [weak store, weak scheduler] reminder, kind in
            store?.log(reminder, kind: kind)
            scheduler?.acknowledged(reminder)
        }

        presenter.onSnooze = { [weak scheduler] reminder, minutes in
            scheduler?.snoozed(reminder, minutes: minutes)
        }

        presenter.progressProvider = { [weak store] reminder in
            guard let store,
                  let target = reminder.dailyTarget, target > 0,
                  let unit = reminder.unit
            else { return nil }
            return "\(Fmt.amountString(store.today.total(for: reminder.id))) / \(Fmt.amountString(target)) \(unit)"
        }





        commandBar.onLog = { [weak self] reminder, kind in
            guard let self else { return }
            if !self.presenter.answerElsewhere(reminder, kind: kind) {
                self.store.log(reminder, kind: kind)
                self.scheduler.acknowledged(reminder)
            }
        }
        commandBar.onOpenSettings = { [weak self] in self?.openSettings() }
        commandBar.registerHotKey()

        store.$config
            .map(\.hotKey)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak commandBar] _ in commandBar?.registerHotKey() }
            .store(in: &cancellables)


        scheduler.start()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if GlassProbe.runIfRequested() || WindowCapture.runIfRequested() || SmokeTest.runIfRequested() {
            NSApp.terminate(nil)
            return
        }
        // Menu bar and floating island only. No Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct CadenceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            PanelView(onOpenSettings: showSettings)
                .environmentObject(model.store)
                .environmentObject(model.scheduler)
                .onAppear { model.openSettings = showSettings }
        } label: {
            MenuBarLabel(scheduler: model.scheduler, store: model.store)
        }
        .menuBarExtraStyle(.window)

        Window("Cadence Settings", id: "settings") {
            SettingsView()
                .environmentObject(model.store)
                .environmentObject(model.scheduler)
        }
        .defaultSize(width: 900, height: 660)
        .windowStyle(.hiddenTitleBar)
        .commandsRemoved()
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }
}

/// What sits in the menu bar: the icon of whatever is next, plus how long you
/// have. Rendered as a template image, so it always matches the menu bar.
private struct MenuBarLabel: View {
    @ObservedObject var scheduler: Scheduler
    @ObservedObject var store: Store

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if store.config.menuBarCountdown, let text = countdownText {
                Text(text)
                    .font(.ui(11, .medium))
                    .monospacedDigit()
            }
        }
    }

    private var symbol: String {
        if scheduler.isPaused { return "pause.circle" }
        return scheduler.upcoming.first?.reminder.symbol ?? "circle.hexagongrid"
    }

    private var countdownText: String? {
        if scheduler.isPaused { return "paused" }
        guard let next = scheduler.upcoming.first else { return nil }
        let seconds = Int(next.fireAt.timeIntervalSince(scheduler.now))
        if seconds <= 0 { return "now" }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h"
    }
}
