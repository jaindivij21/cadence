import AppKit
import SwiftUI

/// Decides how loudly a due reminder arrives and owns the windows that carry
/// it. Quiet alerts morph the island in place; loud ones take over every
/// screen. Only one is live at a time — anything else waits in the queue.
@MainActor
final class AlertPresenter: ObservableObject {

    /// Live countdown for the blocking overlay, observed by every screen's copy.
    final class BreakSession: ObservableObject {
        @Published var reminder: Reminder
        @Published var remaining: Int
        @Published var total: Int
        @Published var canDismiss: Bool = false

        init(reminder: Reminder, seconds: Int) {
            self.reminder = reminder
            self.remaining = seconds
            self.total = max(1, seconds)
        }

        var progress: Double { 1 - (Double(remaining) / Double(total)) }
    }

    @Published private(set) var activeBreak: BreakSession?
    @Published private(set) var activeQuiet: Reminder?

    var onAnswer: ((Reminder, EventKind) -> Void)?
    var onSnooze: ((Reminder, Int) -> Void)?
    /// Optional "1750 / 3000 ml" badge shown alongside the name.
    var progressProvider: ((Reminder) -> String?)?
    /// Called when a full-screen break opens and closes.
    var onBreakChange: ((Bool) -> Void)?
    var soundEnabled: Bool = true

    private let pill = PillController()
    private var queue: [Reminder] = []
    private(set) var overlayWindows: [NSWindow] = []
    private var breakTimer: Timer?
    private var toastTimer: Timer?

    // MARK: - Entry point

    func present(_ reminder: Reminder) {
        guard !queue.contains(where: { $0.id == reminder.id }),
              activeBreak?.reminder.id != reminder.id,
              activeQuiet?.id != reminder.id
        else { return }
        queue.append(reminder)
        drainQueue()
    }

    private func drainQueue() {
        guard activeBreak == nil, activeQuiet == nil, !queue.isEmpty else { return }
        // Blocking alerts jump the queue — they are the ones you cannot miss.
        if let idx = queue.firstIndex(where: { $0.alert.isBlocking }) {
            showBreak(queue.remove(at: idx))
        } else {
            showQuiet(queue.removeFirst())
        }
    }

    /// Clears a reminder that was dismissed without an explicit answer.
    func release(_ reminderID: UUID) {
        queue.removeAll { $0.id == reminderID }
    }

    // MARK: - Full-screen break

    private func showBreak(_ reminder: Reminder) {
        guard case .blocking(let seconds) = reminder.alert else { return }
        let session = BreakSession(reminder: reminder, seconds: seconds)
        activeBreak = session
        onBreakChange?(true)

        for screen in NSScreen.screens {
            let window = KeyableWindow(
                contentRect: screen.frame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.hasShadow = false
            window.setFrame(screen.frame, display: true)

            window.contentView = NSHostingView(
                rootView: BreakOverlayView(
                    session: session,
                    onDone: { [weak self] in self?.finishBreak(kind: .done) },
                    onSkip: { [weak self] in self?.finishBreak(kind: .skipped) }
                )
            )
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                window.animator().alphaValue = 1
            }
            overlayWindows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        play("Submarine")

        // A beat before the buttons light up, so it is a break and not a reflex
        // click.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak session] in
            session?.canDismiss = true
        }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let session = self.activeBreak else { return }
                session.remaining -= 1
                if session.remaining <= 0 { self.finishBreak(kind: .done) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        breakTimer = timer
    }

    private func finishBreak(kind: EventKind) {
        guard let session = activeBreak else { return }
        breakTimer?.invalidate(); breakTimer = nil
        activeBreak = nil
        onAnswer?(session.reminder, kind)
        if kind == .done { play("Glass") }

        let windows = overlayWindows
        overlayWindows = []
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            windows.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            windows.forEach { $0.orderOut(nil) }
        }

        onBreakChange?(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.drainQueue()
        }
    }

    // MARK: - Quiet alert

    private func showQuiet(_ reminder: Reminder) {
        activeQuiet = reminder
        pill.show(
            reminder,
            progress: progressProvider?(reminder),
            onDone: { [weak self] in self?.finishQuiet(kind: .done) },
            onSnooze: { [weak self] in self?.snoozeQuiet(minutes: reminder.snoozeMinutes) },
            onSkip: { [weak self] in self?.finishQuiet(kind: .skipped) }
        )
        play("Tink")

        if case .toast(let sticky) = reminder.alert, !sticky {
            let timer = Timer(timeInterval: 30, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.finishQuiet(kind: .missed) }
            }
            RunLoop.main.add(timer, forMode: .common)
            toastTimer = timer
        }
    }

    private func finishQuiet(kind: EventKind) {
        guard let reminder = activeQuiet else { return }
        toastTimer?.invalidate(); toastTimer = nil
        activeQuiet = nil
        onAnswer?(reminder, kind)
        closeQuiet()
    }

    private func snoozeQuiet(minutes: Int) {
        guard let reminder = activeQuiet else { return }
        toastTimer?.invalidate(); toastTimer = nil
        activeQuiet = nil
        onSnooze?(reminder, minutes)
        closeQuiet()
    }

    private func closeQuiet() {
        pill.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.drainQueue()
        }
    }

    /// Somewhere else answered this reminder — the command bar, the menu bar
    /// panel — so the pill must come down with it.
    @discardableResult
    func answerElsewhere(_ reminder: Reminder, kind: EventKind) -> Bool {
        guard activeQuiet?.id == reminder.id else { return false }
        finishQuiet(kind: kind)
        return true
    }

    // MARK: - Sound

    private func play(_ name: String) {
        guard soundEnabled else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

/// Borderless windows refuse key status by default, which would swallow the
/// escape key on the break overlay.
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
