import AppKit
import SwiftUI

/// Owns every window that is not the menu bar panel: the full-screen break
/// overlay and the corner card. Only one alert is on screen at a time —
/// anything that arrives while another is showing waits in the queue.
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

        var progress: Double {
            1 - (Double(remaining) / Double(total))
        }
    }

    @Published private(set) var activeBreak: BreakSession?
    @Published private(set) var activeToast: Reminder?

    var onAnswer: ((Reminder, EventKind) -> Void)?
    var onSnooze: ((Reminder, Int) -> Void)?
    /// Optional "1750 / 3000 ml" style badge shown on the corner card.
    var progressProvider: ((Reminder) -> String?)?
    var soundEnabled: Bool = true

    private var queue: [Reminder] = []
    private(set) var overlayWindows: [NSWindow] = []
    private var toastWindow: NSPanel?
    private var breakTimer: Timer?
    private var toastTimer: Timer?

    // MARK: - Entry point

    func present(_ reminder: Reminder) {
        guard !queue.contains(where: { $0.id == reminder.id }),
              activeBreak?.reminder.id != reminder.id,
              activeToast?.id != reminder.id
        else { return }
        queue.append(reminder)
        drainQueue()
    }

    private func drainQueue() {
        guard activeBreak == nil, activeToast == nil, !queue.isEmpty else { return }
        // Blocking alerts jump ahead — they are the ones you physically cannot miss.
        if let idx = queue.firstIndex(where: { $0.alert.isBlocking }) {
            let reminder = queue.remove(at: idx)
            showBreak(reminder)
        } else {
            let reminder = queue.removeFirst()
            showToast(reminder)
        }
    }

    // MARK: - Full-screen break

    private func showBreak(_ reminder: Reminder) {
        guard case .blocking(let seconds) = reminder.alert else { return }
        let session = BreakSession(reminder: reminder, seconds: seconds)
        activeBreak = session

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
            window.ignoresMouseEvents = false
            window.setFrame(screen.frame, display: true)

            let root = BreakOverlayView(
                session: session,
                onDone: { [weak self] in self?.finishBreak(kind: .done) },
                onSkip: { [weak self] in self?.finishBreak(kind: .skipped) }
            )
            window.contentView = NSHostingView(rootView: root)
            window.alphaValue = 0
            window.makeKeyAndOrderFront(nil)
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.35
                window.animator().alphaValue = 1
            }
            overlayWindows.append(window)
        }

        NSApp.activate(ignoringOtherApps: true)
        playSound(named: "Submarine")

        // Give a beat before the skip button lights up, so it is a break and not
        // a reflex click.
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
        if kind == .done { playSound(named: "Glass") }

        let windows = overlayWindows
        overlayWindows = []
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            windows.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            windows.forEach { $0.orderOut(nil) }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.drainQueue()
        }
    }

    // MARK: - Corner card

    private func showToast(_ reminder: Reminder) {
        activeToast = reminder

        let width: CGFloat = 380
        let height: CGFloat = 150
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hasShadow = true

        let root = ToastView(
            reminder: reminder,
            progressText: progressProvider?(reminder),
            onDone: { [weak self] in self?.finishToast(kind: .done) },
            onSkip: { [weak self] in self?.finishToast(kind: .skipped) },
            onSnooze: { [weak self] in self?.snoozeToast(minutes: reminder.snoozeMinutes) }
        )
        panel.contentView = NSHostingView(rootView: root)

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let origin = NSPoint(x: visible.maxX - width - 20, y: visible.maxY - height - 20)
            panel.setFrameOrigin(NSPoint(x: origin.x + 24, y: origin.y))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.28
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrameOrigin(origin)
                panel.animator().alphaValue = 1
            }
        } else {
            panel.orderFrontRegardless()
        }

        toastWindow = panel
        playSound(named: "Tink")

        if case .toast(let sticky) = reminder.alert, !sticky {
            let timer = Timer(timeInterval: 30, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.finishToast(kind: .missed) }
            }
            RunLoop.main.add(timer, forMode: .common)
            toastTimer = timer
        }
    }

    private func finishToast(kind: EventKind) {
        guard let reminder = activeToast else { return }
        toastTimer?.invalidate(); toastTimer = nil
        activeToast = nil
        onAnswer?(reminder, kind)
        dismissToastWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.drainQueue()
        }
    }

    private func snoozeToast(minutes: Int) {
        guard let reminder = activeToast else { return }
        toastTimer?.invalidate(); toastTimer = nil
        activeToast = nil
        onSnooze?(reminder, minutes)
        dismissToastWindow()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.drainQueue()
        }
    }

    private func dismissToastWindow() {
        guard let panel = toastWindow else { return }
        toastWindow = nil
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    // MARK: - Sound

    private func playSound(named name: String) {
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
