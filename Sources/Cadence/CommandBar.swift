import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Hot key

/// Which chord summons the bar. ⌘Space belongs to Spotlight, so it is not on
/// the list.
enum HotKeyChoice: String, Codable, CaseIterable, Identifiable {
    case off, optionSpace, controlSpace, commandShiftSpace, commandShiftC

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:               return "Off"
        case .optionSpace:       return "⌥ Space"
        case .controlSpace:      return "⌃ Space"
        case .commandShiftSpace: return "⇧ ⌘ Space"
        case .commandShiftC:     return "⇧ ⌘ C"
        }
    }

    var keyCode: UInt32 {
        switch self {
        case .commandShiftC: return UInt32(kVK_ANSI_C)
        default:             return UInt32(kVK_Space)
        }
    }

    var modifiers: UInt32 {
        switch self {
        case .off:               return 0
        case .optionSpace:       return UInt32(optionKey)
        case .controlSpace:      return UInt32(controlKey)
        case .commandShiftSpace: return UInt32(cmdKey | shiftKey)
        case .commandShiftC:     return UInt32(cmdKey | shiftKey)
        }
    }
}

/// Carbon hot keys are the only way to catch a chord system-wide without asking
/// for accessibility permission, which a reminder app has no business holding.
private var hotKeyActions: [UInt32: () -> Void] = [:]
private var hotKeyHandlerInstalled = false

private func cadenceHotKeyHandler(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var id = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    if let action = hotKeyActions[id.id] {
        DispatchQueue.main.async(execute: action)
    }
    return noErr
}

final class HotKey {
    private var ref: EventHotKeyRef?
    private let identifier: UInt32

    /// Each hot key needs its own id, or registering one tears down the other.
    init(identifier: UInt32 = 1) {
        self.identifier = identifier
    }

    var isRegistered: Bool { ref != nil }

    /// Raw key code and modifier mask, for chords that are not in the picker.
    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        unregister()
        installHandler()
        hotKeyActions[identifier] = action
        let id = EventHotKeyID(signature: OSType(0x43414443), id: identifier) // 'CADC'
        RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    private func installHandler() {
        guard !hotKeyHandlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), cadenceHotKeyHandler, 1, &spec, nil, nil)
        hotKeyHandlerInstalled = true
    }

    func register(_ choice: HotKeyChoice, action: @escaping () -> Void) {
        register(keyCode: choice.keyCode, modifiers: choice.modifiers, action: action)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        hotKeyActions[identifier] = nil
    }

    deinit { unregister() }
}

// MARK: - Commands

/// One runnable line in the bar.
struct Command: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let symbol: String
    let tint: Color
    /// Shown right-aligned: a count, a countdown, a total.
    let trailing: String?
    let run: () -> Void

    /// Subsequence match, the way every launcher does it. Returns nil when the
    /// query does not fit, and a lower score for a better match.
    func score(for query: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let haystack = Array(title.lowercased())
        let needle = Array(query.lowercased())

        var h = 0, n = 0, firstHit: Int?, gaps = 0, lastHit = -1
        while h < haystack.count && n < needle.count {
            if haystack[h] == needle[n] {
                if firstHit == nil { firstHit = h }
                if lastHit >= 0 && h != lastHit + 1 { gaps += 1 }
                lastHit = h
                n += 1
            }
            h += 1
        }
        guard n == needle.count else { return nil }
        // Earlier start and fewer gaps win.
        return (firstHit ?? 0) + gaps * 3
    }
}

// MARK: - Window

/// A borderless panel still has to take key focus, or the search field can
/// never be typed into.
final class CommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The ⌥Space bar: a centred glass panel that lists everything Cadence can do
/// and runs the one you pick. Summoned from anywhere, dismissed with escape.
@MainActor
final class CommandBarController: ObservableObject {
    @Published var query: String = ""
    @Published var selection: Int = 0
    @Published private(set) var visible = false

    private let store: Store
    private let scheduler: Scheduler
    private var panel: CommandPanel?
    private let hotKey = HotKey()
    private var resignObserver: NSObjectProtocol?

    var onOpenSettings: () -> Void = {}
    var onLog: (Reminder, EventKind) -> Void = { _, _ in }
    var onTestPill: ((Reminder) -> Void)?

    init(store: Store, scheduler: Scheduler) {
        self.store = store
        self.scheduler = scheduler
    }

    // MARK: Hot key

    func registerHotKey() {
        guard store.config.hotKey != .off else {
            hotKey.unregister()
            return
        }
        hotKey.register(store.config.hotKey) { [weak self] in
            Task { @MainActor in self?.toggle() }
        }
    }

    // MARK: Showing

    func toggle() {
        visible ? hide() : show()
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        query = ""
        selection = 0
        visible = true

        centre(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.hide() }
            }
        }
    }

    func hide() {
        visible = false
        panel?.orderOut(nil)
    }

    private func makePanel() -> CommandPanel {
        let panel = CommandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 420),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let root = CommandBarView(controller: self)
            .environmentObject(store)
            .environmentObject(scheduler)
            .measure { [weak panel] size in
                guard let panel, size.height > 1 else { return }
                let top = panel.frame.maxY
                panel.setFrame(
                    NSRect(x: panel.frame.minX, y: top - size.height, width: 660, height: size.height),
                    display: true
                )
            }

        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        return panel
    }

    private func centre(_ panel: NSPanel) {
        guard let screen = NSScreen.active else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: visible.midX - panel.frame.width / 2,
            // Slightly above centre, where Spotlight sits. A panel dead centre
            // reads as a modal dialog.
            y: visible.midY - panel.frame.height / 2 + visible.height * 0.12
        ))
    }

    // MARK: Commands

    /// Everything the bar can do, before filtering.
    var allCommands: [Command] {
        var commands: [Command] = []

        for reminder in store.config.reminders where reminder.enabled {
            let done = store.today.takenCount(for: reminder.id)
            let target = slotTarget(reminder)

            commands.append(Command(
                id: "log-\(reminder.id)",
                title: "Log \(reminder.name)",
                subtitle: reminder.actionLabel,
                symbol: reminder.symbol,
                tint: reminder.category.color,
                trailing: trailing(reminder, done: done, target: target)
            ) { [weak self] in
                self?.onLog(reminder, .done)
            })

            if reminder.alert.isBlocking {
                commands.append(Command(
                    id: "start-\(reminder.id)",
                    title: "Start \(reminder.name)",
                    subtitle: "Take over the screen now",
                    symbol: "play.fill",
                    tint: reminder.category.color,
                    trailing: nil
                ) { [weak self] in
                    self?.scheduler.triggerNow(reminder)
                })
            }
        }

        if scheduler.isPaused {
            commands.append(Command(
                id: "resume",
                title: "Resume reminders",
                subtitle: "Start the clocks again",
                symbol: "play.circle",
                tint: .green,
                trailing: nil
            ) { [weak self] in
                self?.scheduler.resume()
            })
        } else {
            for minutes in [15, 30, 60, 180] {
                commands.append(Command(
                    id: "pause-\(minutes)",
                    title: minutes < 60 ? "Pause for \(minutes) minutes" : "Pause for \(minutes / 60) hour\(minutes > 60 ? "s" : "")",
                    subtitle: "Nothing will interrupt you",
                    symbol: "pause.circle",
                    tint: .orange,
                    trailing: nil
                ) { [weak self] in
                    self?.scheduler.pause(minutes: minutes)
                })
            }
        }

        // So a shortcut or a layout change can be checked in five seconds
        // rather than by waiting for the next real reminder.
        if let sample = store.config.reminders.first(where: { !$0.alert.isBlocking && $0.enabled }) {
            commands.append(Command(
                id: "test-pill",
                title: "Test a pill",
                subtitle: "Show one now, to check the shortcut works",
                symbol: "capsule",
                tint: .teal,
                trailing: nil
            ) { [weak self] in
                self?.onTestPill?(sample)
            })
        }

        commands.append(Command(
            id: "settings",
            title: "Settings",
            subtitle: "Reminders, schedules, your day",
            symbol: "gearshape",
            tint: .gray,
            trailing: nil
        ) { [weak self] in
            self?.onOpenSettings()
        })

        commands.append(Command(
            id: "quit",
            title: "Quit Cadence",
            subtitle: nil,
            symbol: "power",
            tint: .red,
            trailing: nil
        ) { [weak self] in
            self?.store.saveNow()
            NSApp.terminate(nil)
        })

        return commands
    }

    /// Filtered and ranked for the current query. Empty query keeps the natural
    /// order so the list does not reshuffle as you delete characters.
    var results: [Command] {
        guard !query.isEmpty else { return allCommands }
        return allCommands
            .compactMap { command in command.score(for: query).map { ($0, command) } }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }

    func runSelected() {
        guard results.indices.contains(selection) else { return }
        let command = results[selection]
        hide()
        command.run()
    }

    func move(_ delta: Int) {
        let count = results.count
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }

    private func slotTarget(_ reminder: Reminder) -> Int? {
        switch reminder.schedule {
        case .everyMinutes:       return nil
        case .timesPerDay(let n): return n
        case .atTimes(let t):     return t.count
        case .beforeEnd:          return 1
        }
    }

    private func trailing(_ reminder: Reminder, done: Int, target: Int?) -> String? {
        if let unit = reminder.unit, let dailyTarget = reminder.dailyTarget, dailyTarget > 0 {
            let total = store.today.total(for: reminder.id)
            return "\(Fmt.amountString(total)) / \(Fmt.amountString(dailyTarget)) \(unit)"
        }
        if let target { return "\(done) of \(target)" }
        return nil
    }
}
