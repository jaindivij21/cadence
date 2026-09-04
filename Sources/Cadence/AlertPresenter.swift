import AppKit
import SwiftUI

/// Decides how loudly a due reminder arrives and owns the windows that carry
/// it. Quiet alerts morph the island in place; loud ones take over every
/// screen. Only one is live at a time — anything else waits in the queue.
@MainActor
final class AlertPresenter: ObservableObject {

    /// One interruption, which may cover several things in order.
    ///
    /// Three different eye drops cannot go in at once — each needs a few
    /// minutes to settle before the next, or the second washes the first out.
    /// So a merged break is a sequence: each step holds the screen for its own
    /// reminder's duration, and that hold *is* the spacing before the next one.
    /// You are interrupted once and asked once.
    final class BreakSession: ObservableObject {
        /// Screen-holding reminders, in order. The first is what triggered it.
        @Published var steps: [Reminder]
        @Published var stepIndex: Int = 0
        @Published var remaining: Int
        @Published var canDismiss: Bool = false
        /// Quiet things worth doing on the same trip. Listed, never tapped —
        /// the one Done at the end covers them.
        @Published var extras: [Reminder] = []

        init(steps: [Reminder]) {
            self.steps = steps
            self.remaining = BreakSession.seconds(of: steps.first)
        }

        static func seconds(of reminder: Reminder?) -> Int {
            guard let reminder, case .blocking(let s) = reminder.alert else { return 20 }
            return max(1, s)
        }

        var current: Reminder { steps[min(stepIndex, steps.count - 1)] }
        var total: Int { BreakSession.seconds(of: current) }
        var progress: Double { 1 - (Double(remaining) / Double(total)) }
        var isLastStep: Bool { stepIndex >= steps.count - 1 }

        /// Everything this interruption stands for.
        var allReminders: [Reminder] { steps + extras }

        /// Advances to the next thing. False when the sequence is finished.
        func advance() -> Bool {
            guard !isLastStep else { return false }
            stepIndex += 1
            remaining = total
            return true
        }
    }

    @Published private(set) var activeBreak: BreakSession?
    @Published private(set) var activeQuiet: Reminder?

    var onAnswer: ((Reminder, EventKind) -> Void)?
    var onSnooze: ((Reminder, Int) -> Void)?
    /// Optional "1750 / 3000 ml" badge shown alongside the name.
    var progressProvider: ((Reminder) -> String?)?
    /// Called when a full-screen break opens and closes.
    var onBreakChange: ((Bool) -> Void)?
    /// Other reminders falling due about now, to be offered in the same breath.
    var companionProvider: ((Reminder) -> [Reminder])?
    /// Tells the scheduler those companions are spoken for.
    var onClaim: (([Reminder]) -> Void)?
    /// Reports when the queue is being held back, so the interface can say so
    /// instead of claiming something is due "now" and then doing nothing.
    var onHold: ((Date?) -> Void)?
    var soundEnabled: Bool = true
    /// Chord that answers the pill, passed straight through to it.
    var pillChord: HotKeyChoice = .controlSpace {
        didSet { pill.chord = pillChord }
    }

    private let pill = PillController()
    private var queue: [Reminder] = []
    private(set) var overlayWindows: [NSWindow] = []
    private var breakTimer: Timer?
    private var toastTimer: Timer?
    /// When the last interruption ended, so the next one cannot tread on it.
    private var lastAlertEnded: Date?
    private var quietCompanions: [Reminder] = []
    private var answeredQuiet: Set<UUID> = []
    private var cooldownTimer: Timer?
    /// Quiet stretch owed after any alert. Set from config each time one fires.
    var minimumGap: TimeInterval = 180

    // MARK: - Entry point

    func present(_ reminder: Reminder) {
        guard !queue.contains(where: { $0.id == reminder.id }),
              activeBreak?.steps.contains { $0.id == reminder.id } != true,
              activeQuiet?.id != reminder.id
        else { return }
        queue.append(reminder)
        drainQueue()
    }

    private func drainQueue() {
        guard activeBreak == nil, activeQuiet == nil, !queue.isEmpty else { return }

        // Answering one reminder buys a stretch of quiet. Without this the eye
        // break ends and the water prompt lands twenty seconds later, which is
        // two interruptions where the point was to have one.
        if let last = lastAlertEnded {
            let waited = Date().timeIntervalSince(last)
            if waited < minimumGap {
                let remaining = minimumGap - waited
                onHold?(Date().addingTimeInterval(remaining))
                scheduleDrain(in: remaining)
                return
            }
        }
        onHold?(nil)

        // Blocking alerts jump the queue — they are the ones you cannot miss.
        if let idx = queue.firstIndex(where: { $0.alert.isBlocking }) {
            showBreak(queue.remove(at: idx))
        } else {
            showQuiet(queue.removeFirst())
        }
    }

    private func scheduleDrain(in seconds: TimeInterval) {
        cooldownTimer?.invalidate()
        let timer = Timer(timeInterval: max(1, seconds), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.drainQueue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        cooldownTimer = timer
    }

    /// Clears a reminder that was dismissed without an explicit answer.
    func release(_ reminderID: UUID) {
        queue.removeAll { $0.id == reminderID }
    }

    // MARK: - Full-screen break

    private func showBreak(_ reminder: Reminder) {
        guard case .blocking(let seconds) = reminder.alert else { return }
        _ = seconds
        let companions = companionProvider?(reminder) ?? []
        // Screen-holders become steps in the sequence; everything else is
        // listed as an extra and swept up by the same single confirmation.
        let session = BreakSession(steps: [reminder] + companions.filter { $0.alert.isBlocking })
        session.extras = companions.filter { !$0.alert.isBlocking }
        onClaim?(companions)
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
                guard session.remaining <= 0 else { return }
                // Roll straight into the next drop rather than closing and
                // interrupting again in five minutes.
                if !session.advance() { self.finishBreak(kind: .done) }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        breakTimer = timer
    }

    private func finishBreak(kind: EventKind) {
        guard let session = activeBreak else { return }
        breakTimer?.invalidate(); breakTimer = nil
        activeBreak = nil

        // One answer covers the whole stop. Steps you already sat through are
        // done regardless — you did them — and only what is left takes the
        // verdict you gave.
        for (index, step) in session.steps.enumerated() {
            let alreadyDone = index < session.stepIndex
            onAnswer?(step, alreadyDone ? .done : kind)
        }
        for extra in session.extras {
            onAnswer?(extra, kind)
        }
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
        lastAlertEnded = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.drainQueue()
        }
    }

    // MARK: - Quiet alert

    private func showQuiet(_ reminder: Reminder) {
        activeQuiet = reminder
        let companions = companionProvider?(reminder) ?? []
        onClaim?(companions)
        quietCompanions = companions
        answeredQuiet = []

        pill.show(
            reminder,
            progress: progressProvider?(reminder),
            companions: companions,
            onDone: { [weak self] in self?.finishQuiet(kind: .done) },
            onSnooze: { [weak self] in self?.snoozeQuiet(minutes: reminder.snoozeMinutes) },
            onSkip: { [weak self] in self?.finishQuiet(kind: .skipped) },
            onCompanion: { [weak self] companion in
                self?.answeredQuiet.insert(companion.id)
                self?.onAnswer?(companion, .done)
            }
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
        // The one answer covers whatever rode along with it.
        for companion in quietCompanions where !answeredQuiet.contains(companion.id) {
            onAnswer?(companion, kind)
        }
        quietCompanions = []
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
        for companion in quietCompanions where !answeredQuiet.contains(companion.id) {
            onAnswer?(companion, .skipped)
        }
        quietCompanions = []
        answeredQuiet = []
        lastAlertEnded = Date()
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
